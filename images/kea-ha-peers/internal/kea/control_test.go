package kea

import (
	"testing"

	"github.com/google/go-cmp/cmp"
	"github.com/google/go-cmp/cmp/cmpopts"
)

func TestCheckResponse(t *testing.T) {
	tests := []struct {
		name    string
		body    string
		wantErr error
	}{
		{
			name: "[positive] resultが0のとき成功する",
			body: `{"result":0,"text":"Configuration successful."}`,
		},
		{
			name:    "[negative] resultが0以外のときErrReloadになる",
			body:    `{"result":1,"text":"Config reload failed"}`,
			wantErr: ErrReload,
		},
		{
			name:    "[negative] resultが無いときErrReloadになる",
			body:    `{"text":"unexpected"}`,
			wantErr: ErrReload,
		},
		{
			name:    "[negative] JSONでないときErrReloadになる",
			body:    `not json`,
			wantErr: ErrReload,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := checkResponse([]byte(tt.body))

			if diff := cmp.Diff(tt.wantErr, err, cmpopts.EquateErrors()); diff != "" {
				t.Errorf("checkResponse() error mismatch (-want +got):\n%s", diff)
			}
		})
	}
}
