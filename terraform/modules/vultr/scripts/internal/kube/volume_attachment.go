package kube

import (
	"context"
	"fmt"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func (c *Client) CountVolumeAttachments(ctx context.Context, nodeName string) (int, error) {
	volumeAttachments, err := c.clientset.StorageV1().
		VolumeAttachments().
		List(ctx, metav1.ListOptions{})
	if err != nil {
		return 0, fmt.Errorf("%w: list volume attachments: %v", ErrKubernetesAPI, err)
	}

	count := 0
	for _, volumeAttachment := range volumeAttachments.Items {
		if volumeAttachment.Spec.NodeName == nodeName {
			count++
		}
	}

	return count, nil
}
