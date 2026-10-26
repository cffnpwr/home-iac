package vultr

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const (
	apiURL = "https://api.vultr.com/v2"
	// Terraformのapplyが応答の無い接続で止まり続けないための上限
	requestTimeout = 30 * time.Second
)

type IsoState string

const (
	IsoStateReady    IsoState = "ready"
	IsoStateMounting IsoState = "isomounting"
	IsoStateMounted  IsoState = "isomounted"
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
	apiKey     string
	httpClient *http.Client
}

func NewClient(apiKey string) *Client {
	return &Client{
		apiKey:     apiKey,
		httpClient: &http.Client{Timeout: requestTimeout},
	}
}

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

func (c *Client) request(ctx context.Context, method string, path string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, method, apiURL+path, nil)
	if err != nil {
		return nil, &APIError{
			Method: method,
			Path:   path,
			Detail: fmt.Sprintf("invalid request: %v", err),
		}
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, &APIError{
			Method: method,
			Path:   path,
			Detail: fmt.Sprintf("request error: %v", err),
		}
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, &APIError{
			Method: method,
			Path:   path,
			Detail: fmt.Sprintf("read response body: %v", err),
		}
	}
	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return nil, &APIError{
			Method: method,
			Path:   path,
			Detail: fmt.Sprintf("status %d, body %s", resp.StatusCode, body),
		}
	}

	return body, nil
}
