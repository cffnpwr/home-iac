package vultr

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

type IsoState string

const (
	IsoStateReady    IsoState = "ready"
	IsoStateMounting IsoState = "isomounting"
	IsoStateMounted  IsoState = "isomounted"
)

func (c *Client) GetIsoState(ctx context.Context, instanceID string) (IsoState, error) {
	path := "/instances/" + instanceID + "/iso"
	body, err := c.request(ctx, http.MethodGet, path)
	if err != nil {
		return "", err
	}

	var resp struct {
		IsoStatus struct {
			State string `json:"state"`
		} `json:"iso_status"`
	}
	if unmarshalErr := json.Unmarshal(body, &resp); unmarshalErr != nil {
		return "", &APIError{
			Method: http.MethodGet,
			Path:   path,
			Detail: fmt.Sprintf("invalid response body: %v", unmarshalErr),
		}
	}

	switch state := IsoState(resp.IsoStatus.State); state {
	case IsoStateReady, IsoStateMounting, IsoStateMounted:
		return state, nil
	}

	return "", &APIError{
		Method: http.MethodGet,
		Path:   path,
		Detail: fmt.Sprintf(
			"unexpected ISO state %q, expected one of %s",
			resp.IsoStatus.State,
			strings.Join(
				[]string{string(IsoStateReady), string(IsoStateMounting), string(IsoStateMounted)},
				", ",
			),
		),
	}
}

func (c *Client) DetachIso(ctx context.Context, instanceID string) error {
	_, err := c.request(ctx, http.MethodPost, "/instances/"+instanceID+"/iso/detach")

	return err
}
