package kea

import (
	"net/netip"
	"testing"
	"text/template"

	"github.com/google/go-cmp/cmp"
	"github.com/google/go-cmp/cmp/cmpopts"

	"github.com/cffnpwr/home-iac/images/kea-ha-peers/internal/peer"
)

func TestRenderConfig(t *testing.T) {
	data := TemplateData{
		Subnet:    netip.MustParsePrefix("192.168.0.0/23"),
		Interface: "end0",
		Self:      netip.MustParseAddr("192.168.0.131"),
		Peers: []peer.Peer{
			{Address: netip.MustParseAddr("192.168.0.129"), Role: peer.RolePrimary},
			{Address: netip.MustParseAddr("192.168.0.131"), Role: peer.RoleStandby},
		},
	}
	tests := []struct {
		name    string
		tmpl    string
		want    string
		wantErr error
	}{
		{
			name: "[positive] JSONとして正しいとき描画結果を返す",
			tmpl: `{"subnet":"{{ .Subnet }}","interface":"{{ .Interface }}","self":"{{ .Self }}","peers":[` +
				`{{ range $i, $p := .Peers }}{{ if $i }},{{ end }}` +
				`{"address":"{{ $p.Address }}","role":"{{ $p.Role }}"}{{ end }}]}`,
			want: `{"subnet":"192.168.0.0/23","interface":"end0","self":"192.168.0.131","peers":[` +
				`{"address":"192.168.0.129","role":"primary"},` +
				`{"address":"192.168.0.131","role":"standby"}]}`,
		},
		{
			name:    "[negative] 描画結果がJSONとして不正なときErrRenderConfigになる",
			tmpl:    `{"peers":[{{ range .Peers }}"{{ .Address }}",{{ end }}]}`,
			wantErr: ErrRenderConfig,
		},
		{
			name:    "[negative] 存在しないフィールドを参照するときErrRenderConfigになる",
			tmpl:    `{"name":"{{ .Name }}"}`,
			wantErr: ErrRenderConfig,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tmpl := template.Must(template.New("config").Option("missingkey=error").Parse(tt.tmpl))

			got, err := RenderConfig(tmpl, data)

			if diff := cmp.Diff(tt.wantErr, err, cmpopts.EquateErrors()); diff != "" {
				t.Fatalf("RenderConfig() error mismatch (-want +got):\n%s", diff)
			}
			if tt.wantErr != nil {
				return
			}
			if diff := cmp.Diff(tt.want, string(got)); diff != "" {
				t.Errorf("RenderConfig() mismatch (-want +got):\n%s", diff)
			}
		})
	}
}
