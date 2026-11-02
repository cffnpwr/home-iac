package main

import (
	"context"
	"fmt"
	"os"
	"time"

	corev1 "k8s.io/api/core/v1"

	"github.com/cffnpwr/home-iac/terraform/modules/vultr/scripts/internal/kube"
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
