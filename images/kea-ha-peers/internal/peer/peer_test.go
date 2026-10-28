package peer

import (
	"net/netip"
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestAssign(t *testing.T) {
	tests := []struct {
		name      string
		addresses []netip.Addr
		want      []Peer
	}{
		{
			name:      "[positive] アドレスが1つのときprimaryだけになる",
			addresses: []netip.Addr{netip.MustParseAddr("192.168.0.129")},
			want: []Peer{
				{Address: netip.MustParseAddr("192.168.0.129"), Role: RolePrimary},
			},
		},
		{
			name: "[positive] 3つ以上のとき小さい順にprimary・standby・backupになる",
			addresses: []netip.Addr{
				netip.MustParseAddr("192.168.0.131"),
				netip.MustParseAddr("192.168.0.20"),
				netip.MustParseAddr("192.168.0.129"),
				netip.MustParseAddr("192.168.0.140"),
			},
			want: []Peer{
				{Address: netip.MustParseAddr("192.168.0.20"), Role: RolePrimary},
				{Address: netip.MustParseAddr("192.168.0.129"), Role: RoleStandby},
				{Address: netip.MustParseAddr("192.168.0.131"), Role: RoleBackup},
				{Address: netip.MustParseAddr("192.168.0.140"), Role: RoleBackup},
			},
		},
		{
			name: "[positive] 重複したアドレスがあるとき1つにまとめる",
			addresses: []netip.Addr{
				netip.MustParseAddr("192.168.0.131"),
				netip.MustParseAddr("192.168.0.129"),
				netip.MustParseAddr("192.168.0.131"),
			},
			want: []Peer{
				{Address: netip.MustParseAddr("192.168.0.129"), Role: RolePrimary},
				{Address: netip.MustParseAddr("192.168.0.131"), Role: RoleStandby},
			},
		},
		{
			name:      "[positive] アドレスが無いとき空になる",
			addresses: nil,
			want:      []Peer{},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Assign(tt.addresses)

			if diff := cmp.Diff(
				tt.want,
				got,
				cmp.Comparer(func(a, b netip.Addr) bool { return a == b }),
			); diff != "" {
				t.Errorf("Assign() mismatch (-want +got):\n%s", diff)
			}
		})
	}
}
