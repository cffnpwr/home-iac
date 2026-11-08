package vultr

import (
	"context"
	"fmt"
	"net/http"
	"strings"
)

type PowerStatus string

const (
	PowerStatusRunning PowerStatus = "running"
	PowerStatusStopped PowerStatus = "stopped"
)

func (c *Client) GetPowerStatus(ctx context.Context, instanceID string) (PowerStatus, error) {
	path := "/instances/" + instanceID
	//nolint:bodyclose // NOTE: govultrが応答のbodyを読み切って閉じる
	instance, _, err := c.client.Instance.Get(ctx, instanceID)
	if err != nil {
		return "", &APIError{Method: http.MethodGet, Path: path, Detail: err.Error()}
	}

	var powerStatus string
	if instance != nil {
		powerStatus = instance.PowerStatus
	}
	switch status := PowerStatus(powerStatus); status {
	case PowerStatusRunning, PowerStatusStopped:
		return status, nil
	}

	return "", &APIError{
		Method: http.MethodGet,
		Path:   path,
		Detail: fmt.Sprintf(
			"unexpected power status %q, expected one of %s",
			powerStatus,
			strings.Join([]string{string(PowerStatusRunning), string(PowerStatusStopped)}, ", "),
		),
	}
}
