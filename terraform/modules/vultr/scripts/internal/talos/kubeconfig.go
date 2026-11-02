package talos

import (
	"context"
	"errors"
	"fmt"

	"github.com/siderolabs/talos/pkg/machinery/client"
)

var ErrFetchKubeconfig = errors.New("fetch kubeconfig failed")

func (c *Client) FetchKubeconfig(ctx context.Context) ([]byte, error) {
	kubeconfig, err := c.talosClient.Kubeconfig(client.WithNode(ctx, c.endpoint))
	if err != nil {
		return nil, fmt.Errorf("%w: from %s: %v", ErrFetchKubeconfig, c.endpoint, err)
	}

	return kubeconfig, nil
}
