package vultr

import (
	"context"
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
	//nolint:bodyclose // NOTE: govultrが応答のbodyを読み切って閉じる
	iso, _, err := c.client.Instance.ISOStatus(ctx, instanceID)
	if err != nil {
		return "", &APIError{Method: http.MethodGet, Path: path, Detail: err.Error()}
	}

	var isoState string
	if iso != nil {
		isoState = iso.State
	}
	switch state := IsoState(isoState); state {
	case IsoStateReady, IsoStateMounting, IsoStateMounted:
		return state, nil
	}

	return "", &APIError{
		Method: http.MethodGet,
		Path:   path,
		Detail: fmt.Sprintf(
			"unexpected ISO state %q, expected one of %s",
			isoState,
			strings.Join(
				[]string{string(IsoStateReady), string(IsoStateMounting), string(IsoStateMounted)},
				", ",
			),
		),
	}
}

func (c *Client) DetachIso(ctx context.Context, instanceID string) error {
	//nolint:bodyclose // NOTE: govultrが応答のbodyを読み切って閉じる
	if _, err := c.client.Instance.DetachISO(ctx, instanceID); err != nil {
		return &APIError{
			Method: http.MethodPost,
			Path:   "/instances/" + instanceID + "/iso/detach",
			Detail: err.Error(),
		}
	}
	return nil
}
