package kube

import (
	"context"
	"errors"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

var (
	ErrInvalidKubeconfig = errors.New("invalid kubeconfig")
	ErrKubernetesAPI     = errors.New("request to Kubernetes API failed")
	ErrNodeBootIDEmpty   = errors.New("node boot ID is empty")
)

type Client struct {
	clientset kubernetes.Interface
}

func NewClient(kubeconfig []byte) (*Client, error) {
	restConfig, err := clientcmd.RESTConfigFromKubeConfig(kubeconfig)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidKubeconfig, err)
	}

	clientset, err := kubernetes.NewForConfig(restConfig)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidKubeconfig, err)
	}

	return &Client{clientset: clientset}, nil
}

func (c *Client) GetNodeReadyStatus(
	ctx context.Context,
	nodeName string,
) (corev1.ConditionStatus, error) {
	node, err := c.getNode(ctx, nodeName)
	if err != nil {
		return "", err
	}

	for _, condition := range node.Status.Conditions {
		if condition.Type == corev1.NodeReady {
			return condition.Status, nil
		}
	}

	return "", nil
}

func (c *Client) GetNodeBootID(ctx context.Context, nodeName string) (string, error) {
	node, err := c.getNode(ctx, nodeName)
	if err != nil {
		return "", err
	}

	if node.Status.NodeInfo.BootID == "" {
		return "", ErrNodeBootIDEmpty
	}

	return node.Status.NodeInfo.BootID, nil
}

func (c *Client) ExistsNode(ctx context.Context, nodeName string) (bool, error) {
	_, err := c.clientset.CoreV1().Nodes().Get(ctx, nodeName, metav1.GetOptions{})
	if apierrors.IsNotFound(err) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("%w: get node %s: %v", ErrKubernetesAPI, nodeName, err)
	}

	return true, nil
}

func (c *Client) DeleteNode(ctx context.Context, nodeName string) error {
	err := c.clientset.CoreV1().Nodes().Delete(ctx, nodeName, metav1.DeleteOptions{})
	if err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("%w: delete node %s: %v", ErrKubernetesAPI, nodeName, err)
	}

	return nil
}

func (c *Client) getNode(ctx context.Context, nodeName string) (*corev1.Node, error) {
	node, err := c.clientset.CoreV1().Nodes().Get(ctx, nodeName, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("%w: get node %s: %v", ErrKubernetesAPI, nodeName, err)
	}

	return node, nil
}
