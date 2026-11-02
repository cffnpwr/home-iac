package vultr

import (
	"context"
	"encoding/json"
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
	body, err := c.request(ctx, http.MethodGet, path)
	if err != nil {
		return "", err
	}

	var resp struct {
		Instance struct {
			PowerStatus string `json:"power_status"`
		} `json:"instance"`
	}
	if unmarshalErr := json.Unmarshal(body, &resp); unmarshalErr != nil {
		return "", &APIError{
			Method: http.MethodGet,
			Path:   path,
			Detail: fmt.Sprintf("invalid response body: %v", unmarshalErr),
		}
	}

	switch status := PowerStatus(resp.Instance.PowerStatus); status {
	case PowerStatusRunning, PowerStatusStopped:
		return status, nil
	}

	return "", &APIError{
		Method: http.MethodGet,
		Path:   path,
		Detail: fmt.Sprintf(
			"unexpected power status %q, expected one of %s",
			resp.Instance.PowerStatus,
			strings.Join([]string{string(PowerStatusRunning), string(PowerStatusStopped)}, ", "),
		),
	}
}
