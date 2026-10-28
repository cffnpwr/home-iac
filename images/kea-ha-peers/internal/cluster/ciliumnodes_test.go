package cluster

import (
	"net/netip"
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestToNode(t *testing.T) {
	tests := []struct {
		name      string
		addresses []ciliumNodeAddress
		want      Node
	}{
		{
			name: "[positive] IPv4のInternalIPとCiliumInternalIPを取り出す",
			addresses: []ciliumNodeAddress{
				{Type: "InternalIP", IP: "192.168.0.129"},
				{Type: "InternalIP", IP: "fd00::1"},
				{Type: "InternalIP", IP: "10.0.0.2"},
				{Type: "CiliumInternalIP", IP: "fd00:10:244::1"},
				{Type: "CiliumInternalIP", IP: "10.244.0.133"},
				{Type: "ExternalIP", IP: "203.0.113.1"},
			},
			want: Node{
				Name: "cpwr-rpi4",
				InternalIPs: []netip.Addr{
					netip.MustParseAddr("192.168.0.129"),
					netip.MustParseAddr("10.0.0.2"),
				},
				CiliumInternalIP: netip.MustParseAddr("10.244.0.133"),
			},
		},
		{
			name: "[negative] IPv4のアドレスが無いとき空のInternalIPsとゼロ値のCiliumInternalIPになる",
			addresses: []ciliumNodeAddress{
				{Type: "InternalIP", IP: "fd00::1"},
				{Type: "CiliumInternalIP", IP: "not an address"},
			},
			want: Node{Name: "cpwr-rpi4", InternalIPs: []netip.Addr{}},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := toNode("cpwr-rpi4", tt.addresses)

			if diff := cmp.Diff(
				tt.want,
				got,
				cmp.Comparer(func(a, b netip.Addr) bool { return a == b }),
			); diff != "" {
				t.Errorf("toNode() mismatch (-want +got):\n%s", diff)
			}
		})
	}
}
