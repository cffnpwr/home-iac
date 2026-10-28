package main

import (
	"errors"
	"fmt"
	"net/netip"
	"slices"

	"github.com/cffnpwr/home-iac/images/kea-ha-peers/internal/cluster"
	"github.com/cffnpwr/home-iac/images/kea-ha-peers/internal/netif"
)

var (
	errSelfNotFound           = errors.New("CiliumNode of this node is not found")
	errNoCiliumInternalIP     = errors.New("CiliumNode has no IPv4 CiliumInternalIP")
	errNoLANAddressInSelfNode = errors.New("CiliumNode has no usable InternalIP in the subnet")
)

type selfNode struct {
	// DHCPを待ち受けるインターフェイスのアドレス
	lanAddress netip.Addr
	// HAのピア間の通信に使うcilium_hostのアドレス
	ciliumInternalIP netip.Addr
}

func findSelf(nodes []cluster.Node, nodeName string, subnet netip.Prefix) (selfNode, error) {
	index := slices.IndexFunc(nodes, func(n cluster.Node) bool { return n.Name == nodeName })
	if index < 0 {
		return selfNode{}, fmt.Errorf("%w: %s", errSelfNotFound, nodeName)
	}
	node := nodes[index]
	if !node.CiliumInternalIP.IsValid() {
		return selfNode{}, fmt.Errorf("%w: %s", errNoCiliumInternalIP, nodeName)
	}

	lanAddress, err := netif.SelectSubnetAddress(node.InternalIPs, subnet)
	if err != nil {
		return selfNode{}, fmt.Errorf("%w: %s: %w", errNoLANAddressInSelfNode, nodeName, err)
	}

	return selfNode{lanAddress: lanAddress, ciliumInternalIP: node.CiliumInternalIP}, nil
}

// CiliumInternalIPを持たないノードは、Ciliumの準備ができるまでピアに含めない
func ciliumInternalIPs(nodes []cluster.Node) []netip.Addr {
	addresses := make([]netip.Addr, 0, len(nodes))
	for _, node := range nodes {
		if node.CiliumInternalIP.IsValid() {
			addresses = append(addresses, node.CiliumInternalIP)
		}
	}

	return addresses
}
