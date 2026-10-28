package main

import (
	"net/netip"
	"testing"

	"github.com/google/go-cmp/cmp"
	"github.com/google/go-cmp/cmp/cmpopts"

	"github.com/cffnpwr/home-iac/images/kea-ha-peers/internal/cluster"
	"github.com/cffnpwr/home-iac/images/kea-ha-peers/internal/netif"
)

var addrComparer = cmp.Comparer(func(a, b netip.Addr) bool { return a == b })

func TestFindSelf(t *testing.T) {
	subnet := netip.MustParsePrefix("192.168.0.0/23")
	tests := []struct {
		name     string
		nodeName string
		nodes    []cluster.Node
		want     selfNode
		wantErr  error
	}{
		{
			name:     "[positive] 自ノードのLANのアドレスとCiliumInternalIPを返す",
			nodeName: "cpwr-rpi4",
			nodes: []cluster.Node{
				{
					Name:             "cpwr-pc",
					InternalIPs:      []netip.Addr{netip.MustParseAddr("192.168.0.131")},
					CiliumInternalIP: netip.MustParseAddr("10.244.1.10"),
				},
				{
					Name: "cpwr-rpi4",
					InternalIPs: []netip.Addr{
						netip.MustParseAddr("10.0.0.2"),
						netip.MustParseAddr("192.168.0.129"),
					},
					CiliumInternalIP: netip.MustParseAddr("10.244.0.133"),
				},
			},
			want: selfNode{
				lanAddress:       netip.MustParseAddr("192.168.0.129"),
				ciliumInternalIP: netip.MustParseAddr("10.244.0.133"),
			},
		},
		{
			name:     "[negative] 自ノードのCiliumNodeが無いときerrSelfNotFoundになる",
			nodeName: "cpwr-rpi4",
			nodes: []cluster.Node{
				{
					Name:             "cpwr-pc",
					InternalIPs:      []netip.Addr{netip.MustParseAddr("192.168.0.131")},
					CiliumInternalIP: netip.MustParseAddr("10.244.1.10"),
				},
			},
			wantErr: errSelfNotFound,
		},
		{
			name:     "[negative] CiliumInternalIPが無いときerrNoCiliumInternalIPになる",
			nodeName: "cpwr-rpi4",
			nodes: []cluster.Node{
				{
					Name:        "cpwr-rpi4",
					InternalIPs: []netip.Addr{netip.MustParseAddr("192.168.0.129")},
				},
			},
			wantErr: errNoCiliumInternalIP,
		},
		{
			name:     "[negative] サブネットに含まれるInternalIPが無いときerrNoLANAddressInSelfNodeになる",
			nodeName: "cpwr-rpi4",
			nodes: []cluster.Node{
				{
					Name:             "cpwr-rpi4",
					InternalIPs:      []netip.Addr{netip.MustParseAddr("10.0.0.2")},
					CiliumInternalIP: netip.MustParseAddr("10.244.0.133"),
				},
			},
			wantErr: errNoLANAddressInSelfNode,
		},
		{
			name:     "[negative] サブネットに含まれるInternalIPが複数あるときErrAmbiguousAddressになる",
			nodeName: "cpwr-rpi4",
			nodes: []cluster.Node{
				{
					Name: "cpwr-rpi4",
					InternalIPs: []netip.Addr{
						netip.MustParseAddr("192.168.0.129"),
						netip.MustParseAddr("192.168.1.129"),
					},
					CiliumInternalIP: netip.MustParseAddr("10.244.0.133"),
				},
			},
			wantErr: netif.ErrAmbiguousAddress,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := findSelf(tt.nodes, tt.nodeName, subnet)

			if diff := cmp.Diff(tt.wantErr, err, cmpopts.EquateErrors()); diff != "" {
				t.Fatalf("findSelf() error mismatch (-want +got):\n%s", diff)
			}
			if diff := cmp.Diff(
				tt.want,
				got,
				cmp.AllowUnexported(selfNode{}),
				addrComparer,
			); diff != "" {
				t.Errorf("findSelf() mismatch (-want +got):\n%s", diff)
			}
		})
	}
}

func TestCiliumInternalIPs(t *testing.T) {
	tests := []struct {
		name  string
		nodes []cluster.Node
		want  []netip.Addr
	}{
		{
			name: "[positive] CiliumInternalIPを持つノードのアドレスだけを返す",
			nodes: []cluster.Node{
				{Name: "cpwr-rpi4", CiliumInternalIP: netip.MustParseAddr("10.244.0.133")},
				{Name: "cpwr-pc"},
				{Name: "cpwr-nas", CiliumInternalIP: netip.MustParseAddr("10.244.3.1")},
			},
			want: []netip.Addr{
				netip.MustParseAddr("10.244.0.133"),
				netip.MustParseAddr("10.244.3.1"),
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ciliumInternalIPs(tt.nodes)

			if diff := cmp.Diff(tt.want, got, addrComparer); diff != "" {
				t.Errorf("ciliumInternalIPs() mismatch (-want +got):\n%s", diff)
			}
		})
	}
}
