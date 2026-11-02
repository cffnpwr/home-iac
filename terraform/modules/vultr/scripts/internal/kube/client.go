package kube

import (
	"errors"
	"fmt"

	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

var (
	ErrInvalidKubeconfig = errors.New("invalid kubeconfig")
	ErrKubernetesAPI     = errors.New("request to Kubernetes API failed")
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
