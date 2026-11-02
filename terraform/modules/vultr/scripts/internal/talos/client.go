package talos

import (
	"context"
	"errors"
	"fmt"

	"github.com/siderolabs/talos/pkg/machinery/client"
	clientconfig "github.com/siderolabs/talos/pkg/machinery/client/config"
)

var ErrCreateClient = errors.New("create Talos client failed")

type Client struct {
	talosClient *client.Client
	endpoint    string
}

func NewClient(
	ctx context.Context,
	talosconfig *clientconfig.Config,
	endpoint string,
) (*Client, error) {
	talosClient, err := client.New(
		ctx,
		client.WithConfig(talosconfig),
		client.WithEndpoints(endpoint),
	)
	if err != nil {
		return nil, fmt.Errorf("%w: for %s: %v", ErrCreateClient, endpoint, err)
	}

	return &Client{talosClient: talosClient, endpoint: endpoint}, nil
}

func (c *Client) Close() error {
	return c.talosClient.Close()
}
