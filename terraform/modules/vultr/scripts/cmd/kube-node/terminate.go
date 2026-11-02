package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/cffnpwr/home-iac/terraform/modules/vultr/scripts/internal/kube"
	"github.com/cffnpwr/home-iac/terraform/modules/vultr/scripts/internal/talos"
	"github.com/cffnpwr/home-iac/terraform/modules/vultr/scripts/internal/vultr"
)

type terminateTarget struct {
	nodeName    string
	nodeAddress string
	instanceID  string
}

func terminateNode(
	ctx context.Context,
	cluster *kube.Client,
	vultrClient *vultr.Client,
	talosClient *talos.Client,
	target terminateTarget,
) error {
	powerStatus, err := vultrClient.GetPowerStatus(ctx, target.instanceID)
	if err != nil {
		return err
	}

	switch powerStatus {
	case vultr.PowerStatusStopped:
		// reset済みのノードにはTalos APIで接続できないため、resetを要求しない
		fmt.Fprintf(os.Stdout, "Instance %s is already stopped\n", target.instanceID)
	case vultr.PowerStatusRunning:
		if resetErr := resetNode(
			ctx,
			cluster,
			vultrClient,
			talosClient,
			target,
		); resetErr != nil {
			return resetErr
		}
	}

	return deleteNode(ctx, cluster, target.nodeName)
}

func resetNode(
	ctx context.Context,
	cluster *kube.Client,
	vultrClient *vultr.Client,
	talosClient *talos.Client,
	target terminateTarget,
) error {
	if err := cluster.DrainNode(ctx, target.nodeName, waitTimeout); err != nil {
		return err
	}

	if err := waitVolumesDetached(ctx, cluster, target.nodeName); err != nil {
		return err
	}

	if err := talosClient.RequestReset(ctx, target.nodeAddress); err != nil {
		return err
	}

	fmt.Fprintf(
		os.Stdout,
		"Requested reset of node %s, waiting for instance %s to stop\n",
		target.nodeName,
		target.instanceID,
	)
	return waitInstanceStopped(ctx, vultrClient, target.instanceID)
}

func waitVolumesDetached(ctx context.Context, cluster *kube.Client, nodeName string) error {
	deadline := time.Now().Add(waitTimeout)
	for time.Now().Before(deadline) {
		count, err := cluster.CountVolumeAttachments(ctx, nodeName)
		if err != nil {
			return err
		}

		if count == 0 {
			return nil
		}

		if waitErr := waitPollInterval(ctx); waitErr != nil {
			return waitErr
		}
	}

	return fmt.Errorf("volumes were not detached from node %s within %s", nodeName, waitTimeout)
}

func waitInstanceStopped(ctx context.Context, vultrClient *vultr.Client, instanceID string) error {
	deadline := time.Now().Add(waitTimeout)
	for time.Now().Before(deadline) {
		powerStatus, err := vultrClient.GetPowerStatus(ctx, instanceID)
		if err != nil {
			return err
		}

		// Talosはresetの全フェーズが成功した後に電源を切るため、停止をresetの完了とみなす
		if powerStatus == vultr.PowerStatusStopped {
			fmt.Fprintf(os.Stdout, "Instance %s is stopped\n", instanceID)
			return nil
		}

		if waitErr := waitPollInterval(ctx); waitErr != nil {
			return waitErr
		}
	}

	return fmt.Errorf("instance %s did not stop within %s", instanceID, waitTimeout)
}

func deleteNode(ctx context.Context, cluster *kube.Client, nodeName string) error {
	if err := cluster.DeleteNode(ctx, nodeName); err != nil {
		return fmt.Errorf("failed to delete node %s: %w", nodeName, err)
	}

	deadline := time.Now().Add(waitTimeout)
	for time.Now().Before(deadline) {
		exists, err := cluster.ExistsNode(ctx, nodeName)
		if err != nil {
			return fmt.Errorf("failed to delete node %s: %w", nodeName, err)
		}

		if !exists {
			fmt.Fprintf(os.Stdout, "Node %s is deleted or did not exist\n", nodeName)
			return nil
		}

		if waitErr := waitPollInterval(ctx); waitErr != nil {
			return waitErr
		}
	}

	return fmt.Errorf("node %s was not deleted within %s", nodeName, waitTimeout)
}
