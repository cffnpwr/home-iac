package netif

import (
	"net/netip"
	"testing"

	"github.com/google/go-cmp/cmp"
	"github.com/google/go-cmp/cmp/cmpopts"
)

func TestFindInterfaceName(t *testing.T) {
	interfaces := []interfaceAddresses{
		{name: "lo", prefixes: []netip.Prefix{netip.MustParsePrefix("127.0.0.1/8")}},
		{
			name: "end0",
			prefixes: []netip.Prefix{
				netip.MustParsePrefix("fe80::1/64"),
				netip.MustParsePrefix("192.168.0.129/23"),
			},
		},
	}
	tests := []struct {
		name    string
		address netip.Addr
		want    string
		wantErr error
	}{
		{
			name:    "[positive] アドレスを持つインターフェイスがあるときその名前を返す",
			address: netip.MustParseAddr("192.168.0.129"),
			want:    "end0",
		},
		{
			name:    "[negative] アドレスを持つインターフェイスが無いときErrInterfaceNotFoundになる",
			address: netip.MustParseAddr("192.168.0.131"),
			wantErr: ErrInterfaceNotFound,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := findInterfaceName(interfaces, tt.address)

			if diff := cmp.Diff(tt.wantErr, err, cmpopts.EquateErrors()); diff != "" {
				t.Fatalf("findInterfaceName() error mismatch (-want +got):\n%s", diff)
			}
			if diff := cmp.Diff(tt.want, got); diff != "" {
				t.Errorf("findInterfaceName() mismatch (-want +got):\n%s", diff)
			}
		})
	}
}
