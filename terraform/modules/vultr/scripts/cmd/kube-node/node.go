package main

import (
	"context"
	"fmt"
	"os"
	"time"

	corev1 "k8s.io/api/core/v1"

	"github.com/cffnpwr/home-iac/terraform/modules/vultr/scripts/internal/kube"
	"github.com/cffnpwr/home-iac/terraform/modules/vultr/scripts/internal/vultr"
)

// 新しいインスタンスの作成と再起動の待機時間
const (
	waitTimeout  = 15 * time.Minute
	pollInterval = 10 * time.Second
)

func waitReady(ctx context.Context, cluster *kube.Client, nodeName string) error {
	deadline := time.Now().Add(waitTimeout)
	lastStatus := ""
	for time.Now().Before(deadline) {
		status, err := cluster.GetNodeReadyStatus(ctx, nodeName)
		switch {
		case err != nil:
			lastStatus = err.Error()
		case status == corev1.ConditionTrue:
			fmt.Fprintf(os.Stdout, "Node %s is Ready\n", nodeName)
			return nil
		default:
			lastStatus = "Ready=" + string(status)
		}

		if waitErr := waitPollInterval(ctx); waitErr != nil {
			return waitErr
		}
	}

	return fmt.Errorf(
		"node %s did not become Ready within %s, last status: %s",
		nodeName,
		waitTimeout,
		lastStatus,
	)
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

func waitPollInterval(ctx context.Context) error {
	timer := time.NewTimer(pollInterval)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}
