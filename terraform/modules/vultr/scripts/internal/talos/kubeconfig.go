package talos

import (
	"context"
	"errors"
	"fmt"

	"github.com/siderolabs/talos/pkg/machinery/client"
	clientconfig "github.com/siderolabs/talos/pkg/machinery/client/config"
)

var ErrFetchKubeconfig = errors.New("fetch kubeconfig failed")

func FetchKubeconfig(
	ctx context.Context,
	talosconfig *clientconfig.Config,
	endpoint string,
) ([]byte, error) {
	talosClient, err := client.New(
		ctx,
		client.WithConfig(talosconfig),
		client.WithEndpoints(endpoint),
	)
	if err != nil {
		return nil, fmt.Errorf(
			"%w: create Talos client for %s: %v",
			ErrFetchKubeconfig,
			endpoint,
			err,
		)
	}
	defer func() { _ = talosClient.Close() }()

	kubeconfig, err := talosClient.Kubeconfig(client.WithNode(ctx, endpoint))
	if err != nil {
		return nil, fmt.Errorf("%w: from %s: %v", ErrFetchKubeconfig, endpoint, err)
	}

	return kubeconfig, nil
}
