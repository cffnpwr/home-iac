package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/cffnpwr/home-iac/terraform/modules/vultr/scripts/internal/kube"
	"github.com/cffnpwr/home-iac/terraform/modules/vultr/scripts/internal/vultr"
)

func detachIso(
	ctx context.Context,
	cluster *kube.Client,
	vultrClient *vultr.Client,
	instanceID string,
	nodeName string,
) error {
	isoState := vultr.IsoStateMounting
	for isoState == vultr.IsoStateMounting {
		var err error
		isoState, err = vultrClient.GetIsoState(ctx, instanceID)
		if err != nil {
			return err
		}

		if waitErr := waitPollInterval(ctx); waitErr != nil {
			return waitErr
		}
	}

	switch isoState {
	case vultr.IsoStateReady:
		fmt.Fprintf(os.Stdout, "Instance %s has no ISO attached\n", instanceID)
		return nil
	case vultr.IsoStateMounting:
		panic(fmt.Sprintf("unreachable ISO state: %q", isoState))
	case vultr.IsoStateMounted:
		bootID, bootIDErr := cluster.GetNodeBootID(ctx, nodeName)
		if bootIDErr != nil {
			return fmt.Errorf("failed to get boot ID of node %s: %w", nodeName, bootIDErr)
		}

		if detachErr := vultrClient.DetachIso(ctx, instanceID); detachErr != nil {
			return detachErr
		}

		fmt.Fprintf(
			os.Stdout,
			"Detached ISO from instance %s, waiting for node %s to reboot\n",
			instanceID,
			nodeName,
		)
		return waitRebooted(ctx, cluster, nodeName, bootID)
	}

	panic(fmt.Sprintf("unreachable ISO state: %q", isoState))
}

func waitRebooted(
	ctx context.Context,
	cluster *kube.Client,
	nodeName string,
	previousBootID string,
) error {
	deadline := time.Now().Add(waitTimeout)
	for time.Now().Before(deadline) {
		bootID, err := cluster.GetNodeBootID(ctx, nodeName)
		if err != nil {
			fmt.Fprintf(os.Stdout, "Failed to get boot ID of node %s: %v\n", nodeName, err)
		} else if bootID != previousBootID {
			return waitReady(ctx, cluster, nodeName)
		}

		if waitErr := waitPollInterval(ctx); waitErr != nil {
			return waitErr
		}
	}

	return fmt.Errorf("node %s did not reboot within %s", nodeName, waitTimeout)
}
