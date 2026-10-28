package cluster

import (
	"context"
	"errors"
	"fmt"
	"net/netip"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/dynamic/dynamicinformer"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
)

// Ciliumのpkg/node/addressingのAddressType
const (
	addressTypeInternalIP       = "InternalIP"
	addressTypeCiliumInternalIP = "CiliumInternalIP"
)

var ciliumNodeResource = schema.GroupVersionResource{
	Group:    "cilium.io",
	Version:  "v2",
	Resource: "ciliumnodes",
}

var (
	ErrConnectCluster = errors.New("connect to Kubernetes API failed")
	ErrSyncNodes      = errors.New("sync CiliumNodes from Kubernetes API failed")
	ErrListNodes      = errors.New("list CiliumNodes failed")
)

type Node struct {
	Name        string
	InternalIPs []netip.Addr
	// ノードのcilium_hostのアドレス。無い場合はゼロ値
	CiliumInternalIP netip.Addr
}

type ciliumNode struct {
	Spec struct {
		Addresses []ciliumNodeAddress `json:"addresses"`
	} `json:"spec"`
}

type ciliumNodeAddress struct {
	Type string `json:"type"`
	IP   string `json:"ip"`
}

type NodeWatcher struct {
	factory  dynamicinformer.DynamicSharedInformerFactory
	informer cache.SharedIndexInformer
	lister   cache.GenericLister
}

func NewNodeWatcher(labelSelector string, onChanged func()) (*NodeWatcher, error) {
	restConfig, err := rest.InClusterConfig()
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrConnectCluster, err)
	}

	client, err := dynamic.NewForConfig(restConfig)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrConnectCluster, err)
	}

	factory := dynamicinformer.NewFilteredDynamicSharedInformerFactory(
		client,
		0,
		metav1.NamespaceAll,
		// NOTE: CiliumNodeにはNodeのラベルが複製されるため、Nodeと同じラベルで選択
		func(options *metav1.ListOptions) { options.LabelSelector = labelSelector },
	)
	nodes := factory.ForResource(ciliumNodeResource)
	handle := func(any) { onChanged() }
	r := cache.ResourceEventHandlerFuncs{
		AddFunc:    handle,
		UpdateFunc: func(_, _ any) { onChanged() },
		DeleteFunc: handle,
	}
	if _, handlerErr := nodes.Informer().AddEventHandler(r); handlerErr != nil {
		return nil, fmt.Errorf("%w: %v", ErrConnectCluster, handlerErr)
	}

	return &NodeWatcher{
		factory:  factory,
		informer: nodes.Informer(),
		lister:   nodes.Lister(),
	}, nil
}

func (w *NodeWatcher) Start(ctx context.Context) error {
	w.factory.Start(ctx.Done())
	if !cache.WaitForCacheSync(ctx.Done(), w.informer.HasSynced) {
		return ErrSyncNodes
	}

	return nil
}

func (w *NodeWatcher) Nodes() ([]Node, error) {
	objects, err := w.lister.List(labels.Everything())
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrListNodes, err)
	}

	nodes := make([]Node, 0, len(objects))
	for _, object := range objects {
		u, ok := object.(*unstructured.Unstructured)
		if !ok {
			panic(fmt.Sprintf("unexpected object type in CiliumNode lister: %T", object))
		}

		var parsed ciliumNode
		if convertErr := runtime.DefaultUnstructuredConverter.FromUnstructured(
			u.Object,
			&parsed,
		); convertErr != nil {
			return nil, fmt.Errorf("%w: %s: %v", ErrListNodes, u.GetName(), convertErr)
		}
		nodes = append(nodes, toNode(u.GetName(), parsed.Spec.Addresses))
	}

	return nodes, nil
}

func toNode(name string, addresses []ciliumNodeAddress) Node {
	node := Node{Name: name, InternalIPs: []netip.Addr{}}
	for _, address := range addresses {
		ip, err := netip.ParseAddr(address.IP)
		// IPv4のアドレスだけを使用
		if err != nil || !ip.Is4() {
			continue
		}

		switch address.Type {
		case addressTypeInternalIP:
			node.InternalIPs = append(node.InternalIPs, ip)
		case addressTypeCiliumInternalIP:
			node.CiliumInternalIP = ip
		}
	}

	return node
}
