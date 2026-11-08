package r2

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/cloudflare/cloudflare-go/v7"
	"github.com/cloudflare/cloudflare-go/v7/accounts"
	"github.com/cloudflare/cloudflare-go/v7/option"
)

const (
	// 応答のない接続でterraformの実行が止まり続けないための上限
	requestTimeout = 30 * time.Second
	maxRetries     = 3
)

var ErrVerifyToken = errors.New("verify Cloudflare API token failed")

type Credentials struct {
	AccessKeyID     string
	SecretAccessKey string
}

func NewCredentials(ctx context.Context, accountID, apiToken string) (Credentials, error) {
	// NOTE: R2のAccess Key IDはAPIトークンのID、Secret Access KeyはAPIトークンの値をSHA-256でハッシュ化した値
	//       https://developers.cloudflare.com/r2/api/tokens/
	tokenID, err := verifyAccountToken(ctx, accountID, apiToken)
	if err != nil {
		return Credentials{}, err
	}

	digest := sha256.Sum256([]byte(apiToken))
	return Credentials{
		AccessKeyID:     tokenID,
		SecretAccessKey: hex.EncodeToString(digest[:]),
	}, nil
}

// アカウントのAPIトークンを検証しトークンのIDを返す
func verifyAccountToken(ctx context.Context, accountID, apiToken string) (string, error) {
	// NOTE: cloudflare.NewClientは環境変数の認証情報とBase URLを読むため、引数の値だけを使うようにTokenServiceを直接作る
	tokens := accounts.NewTokenService(
		option.WithEnvironmentProduction(),
		option.WithAPIToken(apiToken),
		option.WithHTTPClient(&http.Client{Timeout: requestTimeout / maxRetries}),
		option.WithMaxRetries(maxRetries),
	)
	verified, err := tokens.Verify(
		ctx,
		accounts.TokenVerifyParams{AccountID: cloudflare.F(accountID)},
	)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrVerifyToken, err)
	}
	if verified.ID == "" {
		return "", fmt.Errorf("%w: response does not contain the token ID", ErrVerifyToken)
	}
	return verified.ID, nil
}
