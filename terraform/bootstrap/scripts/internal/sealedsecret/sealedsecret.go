package sealedsecret

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"os"

	ssv1alpha1 "github.com/bitnami/sealed-secrets/pkg/apis/sealedsecrets/v1alpha1"
	"github.com/bitnami/sealed-secrets/pkg/kubeseal"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/scheme"
)

// 暗号文だけを含むファイルのためリポジトリの他のファイルと同じ権限にする
const sealedSecretFileMode = 0o644

var ErrSeal = errors.New("seal Secret failed")

type Target struct {
	// 封入に使う、sealed-secrets controllerの証明書（PEM）のパス
	CertPath string
	// SealedSecretを書き込むリポジトリのルートのパス
	RepoRoot string
	// RepoRootを起点としたSealedSecretのファイルのパス
	Path      string
	Namespace string
	Name      string
}

func Write(target Target, data map[string][]byte) error {
	certPEM, err := os.ReadFile(target.CertPath)
	if err != nil {
		return fmt.Errorf("%w: read certificate %s: %v", ErrSeal, target.CertPath, err)
	}
	certSHA256, err := fingerprintCert(target.CertPath, certPEM)
	if err != nil {
		return err
	}
	// NOTE: kubesealのCLIと同じく期限切れの証明書を拒否するためkubeseal.ParseKeyで公開鍵を取り出す
	publicKey, err := kubeseal.ParseKey(bytes.NewReader(certPEM))
	if err != nil {
		return fmt.Errorf("%w: parse certificate %s: %v", ErrSeal, target.CertPath, err)
	}

	sealedSecret, err := ssv1alpha1.NewSealedSecret(scheme.Codecs, publicKey, &corev1.Secret{
		APIVersion: "v1",
		Kind:       "Secret",
		Name:       target.Name,
		Namespace:  target.Namespace,
		Data:       data,
	})
	if err != nil {
		return fmt.Errorf("%w: %v", ErrSeal, err)
	}
	// kubernetes/scripts/seal-terraform-outputs.shと同じく証明書のSHA-256をhome-iac/cert-sha256に記録する
	metav1.SetMetaDataAnnotation(&sealedSecret.ObjectMeta, "home-iac/cert-sha256", certSHA256)

	manifest, err := encodeYAML(sealedSecret)
	if err != nil {
		return err
	}
	// NOTE: Pathがリポジトリのルートの外を指す場合に書き込まないようにos.Rootで書き込む
	root, err := os.OpenRoot(target.RepoRoot)
	if err != nil {
		return fmt.Errorf("%w: open %s: %v", ErrSeal, target.RepoRoot, err)
	}
	defer func() { _ = root.Close() }()
	if err = root.WriteFile(target.Path, manifest, sealedSecretFileMode); err != nil {
		return fmt.Errorf("%w: write %s: %v", ErrSeal, target.Path, err)
	}
	return nil
}

// kubesealの--format yamlと同じエンコーダーでSealedSecretをYAMLにする
func encodeYAML(sealedSecret *ssv1alpha1.SealedSecret) ([]byte, error) {
	info, ok := runtime.SerializerInfoForMediaType(
		scheme.Codecs.SupportedMediaTypes(),
		runtime.ContentTypeYAML,
	)
	if !ok {
		return nil, fmt.Errorf("%w: no serializer for %s", ErrSeal, runtime.ContentTypeYAML)
	}
	serializer := info.PrettySerializer
	if serializer == nil {
		serializer = info.Serializer
	}

	encoder := scheme.Codecs.EncoderForVersion(serializer, ssv1alpha1.SchemeGroupVersion)
	manifest, err := runtime.Encode(encoder, sealedSecret)
	if err != nil {
		return nil, fmt.Errorf("%w: encode SealedSecret: %v", ErrSeal, err)
	}
	return manifest, nil
}

func fingerprintCert(path string, certPEM []byte) (string, error) {
	block, _ := pem.Decode(certPEM)
	if block == nil || block.Type != "CERTIFICATE" {
		return "", fmt.Errorf("%w: %s does not contain a CERTIFICATE PEM block", ErrSeal, path)
	}

	digest := sha256.Sum256(block.Bytes)
	return hex.EncodeToString(digest[:]), nil
}
