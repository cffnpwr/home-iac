package manifest

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"time"
)

const (
	listenHost   = "127.0.0.1"
	callbackPath = "/callback"
	stateBytes   = 32
	// GitHubはmanifest flowを1時間以内に完了することを要求する
	registrationTimeout = time.Hour
	readHeaderTimeout   = 10 * time.Second
)

var (
	ErrRegister            = errors.New("register GitHub App from manifest failed")
	ErrRegistrationTimeout = errors.New("GitHub App is not registered before the timeout")
)

var formTemplate = template.Must(template.New("form").Parse(`<!doctype html>
<html>
<body>
<form action="{{.Action}}" method="post">
<input type="hidden" name="manifest" value="{{.Manifest}}">
<noscript><button type="submit">Register the GitHub App</button></noscript>
</form>
<script>document.forms[0].submit()</script>
</body>
</html>
`))

type Manifest struct {
	Name               string            `json:"name"`
	URL                string            `json:"url"`
	HookAttributes     HookAttributes    `json:"hook_attributes"`
	RedirectURL        string            `json:"redirect_url"`
	Public             bool              `json:"public"`
	DefaultPermissions map[string]string `json:"default_permissions"`
	DefaultEvents      []string          `json:"default_events"`
}

type HookAttributes struct {
	URL    string `json:"url"`
	Active bool   `json:"active"`
}

type formData struct {
	Action   string
	Manifest string
}

type callbackResult struct {
	code string
	err  error
}

type Flow struct {
	// GitHub Appを登録する画面のURL（https://github.com/settings/apps/new等）
	NewAppURL string
	Manifest  Manifest
	// 待ち受けを開始した後に、manifestを送信するページのURLを受け取る
	OnListening func(pageURL string)
	// 待ち受けるポート（0の場合はOSが空いているポートを選ぶ）
	ListenPort int
}

func (f Flow) Run(ctx context.Context) (string, error) {
	listenAddress := net.JoinHostPort(listenHost, strconv.Itoa(f.ListenPort))
	listener, err := (&net.ListenConfig{}).Listen(ctx, "tcp", listenAddress)
	if err != nil {
		return "", fmt.Errorf("%w: listen %s: %v", ErrRegister, listenAddress, err)
	}

	state, err := generateState()
	if err != nil {
		return "", err
	}
	baseURL := "http://" + listener.Addr().String()
	page, err := f.renderForm(state, baseURL+callbackPath)
	if err != nil {
		return "", err
	}

	results := make(chan callbackResult, 1)
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write(page)
	})
	mux.HandleFunc("GET "+callbackPath, func(w http.ResponseWriter, r *http.Request) {
		result := readCallback(r.URL.Query(), state)
		if result.err != nil {
			http.Error(w, result.err.Error(), http.StatusBadRequest)
		} else {
			_, _ = fmt.Fprintln(w, "The GitHub App is registered. This page can be closed.")
		}
		select {
		case results <- result:
		default:
		}
	})

	server := &http.Server{Handler: mux, ReadHeaderTimeout: readHeaderTimeout}
	go func() { _ = server.Serve(listener) }()
	defer func() { _ = server.Close() }()

	f.OnListening(baseURL + "/")

	ctx, cancel := context.WithTimeout(ctx, registrationTimeout)
	defer cancel()
	select {
	case result := <-results:
		return result.code, result.err
	case <-ctx.Done():
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return "", ErrRegistrationTimeout
		}
		return "", fmt.Errorf("%w: %v", ErrRegister, ctx.Err())
	}
}

func (f Flow) renderForm(state, redirectURL string) ([]byte, error) {
	manifest := f.Manifest
	manifest.RedirectURL = redirectURL
	encodedManifest, err := json.Marshal(manifest)
	if err != nil {
		return nil, fmt.Errorf("%w: encode manifest: %v", ErrRegister, err)
	}

	action, err := url.Parse(f.NewAppURL)
	if err != nil {
		return nil, fmt.Errorf("%w: parse %q: %v", ErrRegister, f.NewAppURL, err)
	}
	action.RawQuery = url.Values{"state": {state}}.Encode()

	var page bytes.Buffer
	if err = formTemplate.Execute(
		&page,
		formData{Action: action.String(), Manifest: string(encodedManifest)},
	); err != nil {
		return nil, fmt.Errorf("%w: render form: %v", ErrRegister, err)
	}
	return page.Bytes(), nil
}

func generateState() (string, error) {
	state := make([]byte, stateBytes)
	if _, err := rand.Read(state); err != nil {
		return "", fmt.Errorf("%w: generate state: %v", ErrRegister, err)
	}
	return hex.EncodeToString(state), nil
}

func readCallback(query url.Values, expectedState string) callbackResult {
	if subtle.ConstantTimeCompare([]byte(query.Get("state")), []byte(expectedState)) != 1 {
		return callbackResult{
			err: fmt.Errorf("%w: state in the callback does not match", ErrRegister),
		}
	}
	code := query.Get("code")
	if code == "" {
		return callbackResult{err: fmt.Errorf("%w: code is missing in the callback", ErrRegister)}
	}
	return callbackResult{code: code}
}
