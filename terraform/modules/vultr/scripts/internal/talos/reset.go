package talos

import (
	"context"
	"errors"
	"fmt"

	machineapi "github.com/siderolabs/talos/pkg/machinery/api/machine"
	"github.com/siderolabs/talos/pkg/machinery/client"
	"github.com/siderolabs/talos/pkg/machinery/constants"
)

var ErrResetNode = errors.New("reset node failed")

func (c *Client) RequestReset(ctx context.Context, nodeAddress string) error {
	// resetの途中でTalos APIに接続できなくなるため、resetの完了を待たない
	err := c.talosClient.ResetGeneric(client.WithNode(ctx, nodeAddress), &machineapi.ResetRequest{
		Graceful: true,
		Reboot:   false,
		SystemPartitionsToWipe: []*machineapi.ResetPartitionSpec{
			{Label: constants.StatePartitionLabel, Wipe: true},
			{Label: constants.EphemeralPartitionLabel, Wipe: true},
		},
	})
	if err != nil {
		return fmt.Errorf("%w: node %s: %v", ErrResetNode, nodeAddress, err)
	}

	return nil
}
