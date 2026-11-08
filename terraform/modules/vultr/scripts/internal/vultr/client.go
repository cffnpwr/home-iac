package vultr

import (
	"fmt"
	"net/http"
	"time"

	"github.com/vultr/govultr/v3"
	"golang.org/x/oauth2"
)

const (
	// Terraformのapplyが応答のない接続で止まり続けないための上限
	requestTimeout = 30 * time.Second
	maxRetries     = 3
)

type APIError struct {
	Method string
	Path   string
	Detail string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("Vultr API %s %s failed: %s", e.Method, e.Path, e.Detail)
}

type Client struct {
	client *govultr.Client
}

func NewClient(apiKey string) *Client {
	// NOTE: govultrはAPIキーを付けるhttp.Clientを受け取る。golang.org/x/oauth2でAuthorizationヘッダーにBearerトークンとして付ける
	//       https://github.com/vultr/govultr#authentication
	client := govultr.NewClient(&http.Client{
		Transport: &oauth2.Transport{
			Source: oauth2.StaticTokenSource(&oauth2.Token{AccessToken: apiKey}),
		},
		Timeout: requestTimeout / maxRetries,
	})
	// NOTE: govultrは既定で失敗したリクエストを3回まで再試行する。requestTimeoutを1回の呼び出し全体の上限に保つため再試行しない
	client.SetRetryLimit(maxRetries)

	return &Client{client: client}
}
