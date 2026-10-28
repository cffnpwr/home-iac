package kea

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"syscall"
	"time"
)

const (
	controlTimeout = 30 * time.Second
	// Keaの制御コマンドの応答で成功を表すresult
	resultSuccess = 0
)

var (
	ErrControlSocketUnavailable = errors.New("control socket of Kea is unavailable")
	ErrReload                   = errors.New("reload Kea configuration failed")
)

type command struct {
	Command string `json:"command"`
}

type response struct {
	Result *int   `json:"result"`
	Text   string `json:"text"`
}

func Reload(ctx context.Context, socketPath string) error {
	ctx, cancel := context.WithTimeout(ctx, controlTimeout)
	defer cancel()

	var dialer net.Dialer
	conn, err := dialer.DialContext(ctx, "unix", socketPath)
	if errors.Is(err, syscall.ENOENT) || errors.Is(err, syscall.ECONNREFUSED) {
		return fmt.Errorf("%w: %v", ErrControlSocketUnavailable, err)
	}
	if err != nil {
		return fmt.Errorf("%w: %v", ErrReload, err)
	}
	defer conn.Close()

	if deadline, ok := ctx.Deadline(); ok {
		if deadlineErr := conn.SetDeadline(deadline); deadlineErr != nil {
			return fmt.Errorf("%w: %v", ErrReload, deadlineErr)
		}
	}

	if encodeErr := json.NewEncoder(conn).
		Encode(command{Command: "config-reload"}); encodeErr != nil {
		return fmt.Errorf("%w: %v", ErrReload, encodeErr)
	}

	// Keaは応答を送った後に接続を閉じるためEOFまで読み取り
	body, err := io.ReadAll(conn)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrReload, err)
	}

	return checkResponse(body)
}

func checkResponse(body []byte) error {
	var res response
	if err := json.Unmarshal(body, &res); err != nil {
		return fmt.Errorf("%w: invalid response %q: %v", ErrReload, body, err)
	}
	if res.Result == nil {
		return fmt.Errorf("%w: response has no result: %q", ErrReload, body)
	}
	if *res.Result != resultSuccess {
		return fmt.Errorf("%w: result %d: %s", ErrReload, *res.Result, res.Text)
	}

	return nil
}
