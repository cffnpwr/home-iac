package agefile

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"filippo.io/age"
	"filippo.io/age/plugin"
	"filippo.io/age/tag"
)

var (
	ErrRecipients = errors.New("invalid age recipients")
	ErrIdentities = errors.New("invalid age identities")
)

func ParseRecipients(r io.Reader) ([]age.Recipient, error) {
	ui := newTerminalUI()
	var recipients []age.Recipient
	err := scanLines(r, func(line string) error {
		recipient, err := parseRecipient(line, ui)
		if err != nil {
			return fmt.Errorf("%w: %v", ErrRecipients, err)
		}
		recipients = append(recipients, recipient)
		return nil
	})
	if err != nil {
		return nil, err
	}
	if len(recipients) == 0 {
		return nil, fmt.Errorf("%w: no recipients found", ErrRecipients)
	}
	return recipients, nil
}

func ParseIdentities(r io.Reader) ([]age.Identity, error) {
	ui := newTerminalUI()
	var identities []age.Identity
	err := scanLines(r, func(line string) error {
		identity, err := parseIdentity(line, ui)
		if err != nil {
			return fmt.Errorf("%w: %v", ErrIdentities, err)
		}
		identities = append(identities, identity)
		return nil
	})
	if err != nil {
		return nil, err
	}
	if len(identities) == 0 {
		return nil, fmt.Errorf("%w: no identities found", ErrIdentities)
	}
	return identities, nil
}

func parseRecipient(line string, ui *plugin.ClientUI) (age.Recipient, error) {
	// NOTE: age.ParseRecipients・age.ParseIdentitiesはpluginとtagの宛先を扱わない
	//       ageのCLIと同じく宛先・identityの接頭辞で種類を判定する
	switch {
	case strings.HasPrefix(line, "age1tag1") || strings.HasPrefix(line, "age1tagpq1"):
		return tag.ParseRecipient(line)
	case strings.HasPrefix(line, "age1pq1"):
		return age.ParseHybridRecipient(line)
	// NOTE: pluginの宛先はage1<pluginの名前>1<データ>の形式
	case strings.HasPrefix(line, "age1") && strings.Count(line, "1") > 1:
		return plugin.NewRecipient(line, ui)
	case strings.HasPrefix(line, "age1"):
		return age.ParseX25519Recipient(line)
	}
	return nil, fmt.Errorf("unknown recipient type: %q", line)
}

func parseIdentity(line string, ui *plugin.ClientUI) (age.Identity, error) {
	switch {
	case strings.HasPrefix(line, "AGE-PLUGIN-"):
		return plugin.NewIdentity(line, ui)
	case strings.HasPrefix(line, "AGE-SECRET-KEY-1"):
		return age.ParseX25519Identity(line)
	case strings.HasPrefix(line, "AGE-SECRET-KEY-PQ-1"):
		return age.ParseHybridIdentity(line)
	}
	// NOTE: identityは秘密鍵を含みうるためエラーに内容を含めない
	return nil, errors.New("unknown identity type")
}

// 空行と#で始まる行を除いた各行を処理する
func scanLines(r io.Reader, handle func(line string) error) error {
	scanner := bufio.NewScanner(r)
	lineNumber := 0
	for scanner.Scan() {
		lineNumber++
		line := scanner.Text()
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if err := handle(line); err != nil {
			return fmt.Errorf("line %d: %w", lineNumber, err)
		}
	}
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("read lines: %v", err)
	}
	return nil
}

// NOTE: pluginはYubiKeyのPINの入力・タッチの待機等の表示と入力に端末を使う
func newTerminalUI() *plugin.ClientUI {
	return plugin.NewTerminalUI(
		func(format string, v ...any) {
			fmt.Fprintf(os.Stderr, "age: "+format+"\n", v...)
		},
		func(format string, v ...any) {
			fmt.Fprintf(os.Stderr, "age: warning: "+format+"\n", v...)
		},
	)
}
