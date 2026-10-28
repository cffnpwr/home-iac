package netif

import (
	"net/netip"
	"testing"

	"github.com/google/go-cmp/cmp"
	"github.com/google/go-cmp/cmp/cmpopts"
)

func TestSelectSubnetAddress(t *testing.T) {
	subnet := netip.MustParsePrefix("192.168.0.0/23")
	tests := []struct {
		name      string
		addresses []netip.Addr
		want      netip.Addr
		wantErr   error
	}{
		{
			name: "[positive] サブネットに含まれるアドレスが1つのときそのアドレスを返す",
			addresses: []netip.Addr{
				netip.MustParseAddr("10.0.0.2"),
				netip.MustParseAddr("192.168.1.129"),
			},
			want: netip.MustParseAddr("192.168.1.129"),
		},
		{
			name:      "[negative] サブネットに含まれるアドレスが無いときErrNoAddressInSubnetになる",
			addresses: []netip.Addr{netip.MustParseAddr("192.168.2.1")},
			wantErr:   ErrNoAddressInSubnet,
		},
		{
			name: "[negative] サブネットに含まれるアドレスが複数あるときErrAmbiguousAddressになる",
			addresses: []netip.Addr{
				netip.MustParseAddr("192.168.0.129"),
				netip.MustParseAddr("192.168.1.129"),
			},
			wantErr: ErrAmbiguousAddress,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := SelectSubnetAddress(tt.addresses, subnet)

			if diff := cmp.Diff(tt.wantErr, err, cmpopts.EquateErrors()); diff != "" {
				t.Fatalf("SelectSubnetAddress() error mismatch (-want +got):\n%s", diff)
			}
			if diff := cmp.Diff(
				tt.want,
				got,
				cmp.Comparer(func(a, b netip.Addr) bool { return a == b }),
			); diff != "" {
				t.Errorf("SelectSubnetAddress() mismatch (-want +got):\n%s", diff)
			}
		})
	}
}
