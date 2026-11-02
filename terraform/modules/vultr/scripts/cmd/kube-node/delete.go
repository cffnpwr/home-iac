package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/cffnpwr/home-iac/terraform/modules/vultr/scripts/internal/kube"
)

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
