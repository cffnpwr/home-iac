package main

import (
	"net/netip"
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestIsIPv4Network(t *testing.T) {
	tests := []struct {
		name   string
		subnet netip.Prefix
		want   bool
	}{
		{
			name:   "[positive] IPv4のネットワークアドレスのときtrueを返す",
			subnet: netip.MustParsePrefix("192.168.0.0/23"),
			want:   true,
		},
		{
			name:   "[negative] ホスト部が0でないときfalseを返す",
			subnet: netip.MustParsePrefix("192.168.0.129/23"),
		},
		{
			name:   "[negative] IPv6のときfalseを返す",
			subnet: netip.MustParsePrefix("fd00::/64"),
		},
		{
			name:   "[negative] 指定されていないときfalseを返す",
			subnet: netip.Prefix{},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isIPv4Network(tt.subnet)

			if diff := cmp.Diff(tt.want, got); diff != "" {
				t.Errorf("isIPv4Network() mismatch (-want +got):\n%s", diff)
			}
		})
	}
}
