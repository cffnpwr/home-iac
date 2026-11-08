package gh

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"

	"github.com/cli/go-gh/v2/pkg/auth"
	"github.com/google/go-github/v93/github"
	"golang.org/x/crypto/nacl/box"
)

const githubHost = "github.com"

var ErrNoToken = errors.New("no GitHub token found")

type Repository struct {
	Owner string
	Name  string
}

func (r Repository) String() string {
	return r.Owner + "/" + r.Name
}

func NewAPIClient() (*github.Client, error) {
	// NOTE: go-ghはGH_TOKEN・GITHUB_TOKEN環境変数・ghの設定ファイルの順にトークンを探す
	//       トークンがシステムのキーリングにある場合だけ、go-ghはgh auth tokenを実行して取得する
	token, _ := auth.TokenForHost(githubHost)
	if token == "" {
		return nil, fmt.Errorf("%w: set GH_TOKEN or run gh auth login", ErrNoToken)
	}
	client, err := github.NewClient(github.WithAuthToken(token))
	if err != nil {
		return nil, fmt.Errorf("create GitHub API client: %v", err)
	}
	return client, nil
}

func IsNotFound(err error) bool {
	return hasStatus(err, http.StatusNotFound)
}

func SetEnvironmentVariable(
	ctx context.Context,
	client *github.Client,
	repo Repository,
	env, name, value string,
) error {
	// NOTE: ghのvariable setと同じく作成を先に試し、既に存在する場合に返る409で更新に切り替える
	_, err := client.Actions.CreateEnvVariable(
		ctx,
		repo.Owner,
		repo.Name,
		env,
		github.ActionsCreateVariableRequest{Name: name, Value: value},
	)
	if err == nil {
		return nil
	}
	if !hasStatus(err, http.StatusConflict) {
		return fmt.Errorf("create variable %s in environment %q: %v", name, env, err)
	}

	if _, err = client.Actions.UpdateEnvVariable(
		ctx,
		repo.Owner,
		repo.Name,
		env,
		name,
		github.ActionsUpdateVariableRequest{Value: &value},
	); err != nil {
		return fmt.Errorf("update variable %s in environment %q: %v", name, env, err)
	}
	return nil
}

func SetEnvironmentSecret(
	ctx context.Context,
	client *github.Client,
	repo Repository,
	env, name string,
	value []byte,
) error {
	publicKey, _, err := client.Actions.GetEnvPublicKey(ctx, repo.Owner, repo.Name, env)
	if err != nil {
		return fmt.Errorf("get public key of environment %q: %v", env, err)
	}
	encryptedValue, err := encryptSecret(publicKey.GetKey(), value)
	if err != nil {
		return fmt.Errorf("encrypt secret %s for environment %q: %v", name, env, err)
	}

	if _, err = client.Actions.CreateOrUpdateEnvSecret(
		ctx,
		repo.Owner,
		repo.Name,
		env,
		name,
		github.SecretRequest{KeyID: publicKey.GetKeyID(), EncryptedValue: encryptedValue},
	); err != nil {
		return fmt.Errorf("set secret %s in environment %q: %v", name, env, err)
	}
	return nil
}

// GitHub APIの要求に従い、Base64の公開鍵でlibsodiumのsealed boxとして暗号化する
func encryptSecret(encodedPublicKey string, value []byte) (string, error) {
	decoded, err := base64.StdEncoding.DecodeString(encodedPublicKey)
	if err != nil {
		return "", fmt.Errorf("decode public key: %v", err)
	}
	var publicKey [32]byte
	if len(decoded) != len(publicKey) {
		return "", fmt.Errorf("public key must be %d bytes, got %d", len(publicKey), len(decoded))
	}
	copy(publicKey[:], decoded)

	sealed, err := box.SealAnonymous(nil, value, &publicKey, rand.Reader)
	if err != nil {
		return "", fmt.Errorf("seal: %v", err)
	}
	return base64.StdEncoding.EncodeToString(sealed), nil
}

func hasStatus(err error, statusCode int) bool {
	var errorResponse *github.ErrorResponse
	return errors.As(err, &errorResponse) &&
		errorResponse.Response != nil &&
		errorResponse.Response.StatusCode == statusCode
}
