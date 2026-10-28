package kea

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/netip"
	"os"
	"path/filepath"
	"text/template"

	"github.com/cffnpwr/home-iac/images/kea-ha-peers/internal/peer"
)

const configFileMode = 0o644

var (
	ErrRenderConfig = errors.New("render Kea configuration failed")
	ErrWriteConfig  = errors.New("write Kea configuration failed")
)

type TemplateData struct {
	Subnet    netip.Prefix
	Interface string
	Self      netip.Addr
	Peers     []peer.Peer
}

func RenderConfig(tmpl *template.Template, data TemplateData) ([]byte, error) {
	var rendered bytes.Buffer
	if err := tmpl.Execute(&rendered, data); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrRenderConfig, err)
	}
	if !json.Valid(rendered.Bytes()) {
		return nil, fmt.Errorf("%w: rendered configuration is not valid JSON", ErrRenderConfig)
	}

	return rendered.Bytes(), nil
}

func WriteConfig(path string, config []byte) error {
	tmpFile, createErr := os.CreateTemp(filepath.Dir(path), filepath.Base(path)+".*")
	if createErr != nil {
		return fmt.Errorf("%w: %v", ErrWriteConfig, createErr)
	}
	defer os.Remove(tmpFile.Name())

	_, writeErr := tmpFile.Write(config)
	closeErr := tmpFile.Close()
	if err := errors.Join(writeErr, closeErr); err != nil {
		return fmt.Errorf("%w: %v", ErrWriteConfig, err)
	}
	if chmodErr := os.Chmod(tmpFile.Name(), configFileMode); chmodErr != nil {
		return fmt.Errorf("%w: %v", ErrWriteConfig, chmodErr)
	}

	// Keaが書き込み途中のファイルを読まないよう、一時ファイルに書いてから設定ファイルに置き換え
	if renameErr := os.Rename(tmpFile.Name(), path); renameErr != nil {
		return fmt.Errorf("%w: %v", ErrWriteConfig, renameErr)
	}

	return nil
}
