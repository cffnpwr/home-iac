package ssecustomerkey

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"filippo.io/age"
	"go.yaml.in/yaml/v4"

	"github.com/cffnpwr/home-iac/terraform/bootstrap/scripts/internal/agefile"
)

const (
	Path = "terraform/bootstrap/sse-customer-key.age"
	// リポジトリのルートからの、Sealed Secretsの鍵の退避Jobが暗号化に使う宛先のConfigMapのパス
	recipientsPath = "kubernetes/apps/sealed-secrets-backup/recipients.yaml"
	// NOTE: terraformのS3 backendはAWS_SSE_CUSTOMER_KEYに44文字のBase64（32バイト）を要求する
	//       https://github.com/hashicorp/terraform/blob/v1.17.1/internal/backend/remote-state/s3/backend.go#L869-L875
	keySize = 32
	// 暗号文だけを含むファイルのためリポジトリの他のファイルと同じ権限にする
	encryptedFileMode = 0o644
	// SSE-Cの鍵のBase64の文字列を十分に上回る復号の結果の上限
	decryptedSizeLimit = 1 << 10
)

var (
	ErrExists   = errors.New("SSE-C key file already exists")
	ErrGenerate = errors.New("generate SSE-C key failed")
	ErrDecrypt  = errors.New("decrypt SSE-C key failed")
)

type recipientsConfigMap struct {
	Data map[string]string `yaml:"data"`
}

func Generate(repoRoot string) (string, error) {
	keyPath := filepath.Join(repoRoot, Path)
	// NOTE: 鍵を置き換えると既存の鍵で暗号化したbootstrapのstateを復号できなくなる
	if _, err := os.Lstat(keyPath); err == nil {
		return "", fmt.Errorf("%w: %s", ErrExists, keyPath)
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", fmt.Errorf("%w: check %s: %v", ErrGenerate, keyPath, err)
	}

	// NOTE: Sealed Secretsの鍵の退避Jobと同じ宛先に暗号化する
	recipients, err := readRecipients(filepath.Join(repoRoot, recipientsPath))
	if err != nil {
		return "", err
	}

	key := make([]byte, keySize)
	// NOTE: crypto/rand.Readはエラーを返さない
	//       https://pkg.go.dev/crypto/rand#Read
	_, _ = rand.Read(key)

	// NOTE: 平文の鍵をファイルに書き出さないためメモリ上で暗号化する
	var encrypted bytes.Buffer
	writer, err := age.Encrypt(&encrypted, recipients...)
	if err != nil {
		return "", fmt.Errorf("%w: encrypt: %v", ErrGenerate, err)
	}
	// NOTE: openssl rand -base64 32で生成していたときの形式と同じく末尾に改行を付ける
	if _, err = io.WriteString(writer, base64.StdEncoding.EncodeToString(key)+"\n"); err != nil {
		return "", fmt.Errorf("%w: encrypt: %v", ErrGenerate, err)
	}
	if err = writer.Close(); err != nil {
		return "", fmt.Errorf("%w: encrypt: %v", ErrGenerate, err)
	}

	if err = writeNewFile(keyPath, encrypted.Bytes()); err != nil {
		return "", err
	}
	return keyPath, nil
}

func Decrypt(repoRoot, identityPath string) (string, error) {
	keyPath := filepath.Join(repoRoot, Path)
	encrypted, err := os.Open(keyPath)
	if err != nil {
		return "", fmt.Errorf("%w: open %s: %v", ErrDecrypt, keyPath, err)
	}
	defer encrypted.Close()

	identityFile, err := os.Open(identityPath)
	if err != nil {
		return "", fmt.Errorf("%w: open identity file %s: %v", ErrDecrypt, identityPath, err)
	}
	defer identityFile.Close()
	identities, err := agefile.ParseIdentities(identityFile)
	if err != nil {
		return "", fmt.Errorf("%w: identity file %s: %v", ErrDecrypt, identityPath, err)
	}

	reader, err := age.Decrypt(encrypted, identities...)
	if err != nil {
		return "", fmt.Errorf("%w: %s: %v", ErrDecrypt, keyPath, err)
	}
	decrypted, err := io.ReadAll(io.LimitReader(reader, decryptedSizeLimit+1))
	if err != nil {
		return "", fmt.Errorf("%w: %s: %v", ErrDecrypt, keyPath, err)
	}
	if len(decrypted) > decryptedSizeLimit {
		return "", fmt.Errorf(
			"%w: %s: decrypted content exceeds %d bytes",
			ErrDecrypt,
			keyPath,
			decryptedSizeLimit,
		)
	}

	// NOTE: シェルのコマンド置換と同じく末尾の改行を除く
	return strings.TrimRight(string(decrypted), "\n"), nil
}

func readRecipients(path string) ([]age.Recipient, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("%w: read %s: %v", ErrGenerate, path, err)
	}
	var configMap recipientsConfigMap
	if err = yaml.Load(content, &configMap); err != nil {
		return nil, fmt.Errorf("%w: decode %s: %v", ErrGenerate, path, err)
	}
	recipientsText, ok := configMap.Data["recipients.txt"]
	if !ok {
		return nil, fmt.Errorf(
			"%w: %s does not contain data[\"recipients.txt\"]",
			ErrGenerate,
			path,
		)
	}

	recipients, err := agefile.ParseRecipients(strings.NewReader(recipientsText))
	if err != nil {
		return nil, fmt.Errorf("%w: %s: %v", ErrGenerate, path, err)
	}
	return recipients, nil
}

// 既存のファイルを上書きしないためファイルが存在する場合は失敗する
func writeNewFile(path string, content []byte) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, encryptedFileMode)
	if err != nil {
		if errors.Is(err, os.ErrExist) {
			return fmt.Errorf("%w: %s", ErrExists, path)
		}
		return fmt.Errorf("%w: create %s: %v", ErrGenerate, path, err)
	}

	_, err = file.Write(content)
	if err = errors.Join(err, file.Close()); err != nil {
		// NOTE: 途中まで書いたファイルを残すと次の実行が既存のファイルとして停止する
		return errors.Join(
			fmt.Errorf("%w: write %s: %v", ErrGenerate, path, err),
			os.Remove(path),
		)
	}
	return nil
}
