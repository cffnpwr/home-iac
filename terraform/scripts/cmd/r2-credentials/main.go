package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/cffnpwr/home-iac/terraform/scripts/r2"
)

// stepのoutputの名前と値
type output struct {
	name  string
	value string
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// GitHub Actionsのstepで、CLOUDFLARE_API_TOKENのトークンから作ったR2の認証情報をマスクしてstepのoutputに出力
func run() error {
	// NOTE: コマンドライン引数にトークンを置かないため環境変数で受け取る
	accountID, err := requireEnv("CLOUDFLARE_ACCOUNT_ID")
	if err != nil {
		return err
	}
	apiToken, err := requireEnv("CLOUDFLARE_API_TOKEN")
	if err != nil {
		return err
	}
	outputPath, err := requireEnv("GITHUB_OUTPUT")
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	credentials, err := r2.NewCredentials(ctx, accountID, apiToken)
	if err != nil {
		return err
	}
	outputs := []output{
		{name: "aws-access-key-id", value: credentials.AccessKeyID},
		{name: "aws-secret-access-key", value: credentials.SecretAccessKey},
	}

	// NOTE: GitHub Actionsは値をログに出力する前・他のworkflow commandで使う前にadd-maskで登録することを求める
	//       https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#masking-a-value-in-a-log
	for _, o := range outputs {
		// NOTE: 改行を含む値はworkflow commandとoutputのファイルの行の区切りとして解釈される
		if strings.ContainsAny(o.value, "\r\n") {
			return fmt.Errorf("output %s contains a line break", o.name)
		}
		fmt.Fprintf(os.Stdout, "::add-mask::%s\n", o.value)
	}

	return writeOutputs(outputPath, outputs)
}

func writeOutputs(path string, outputs []output) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND, 0)
	if err != nil {
		return fmt.Errorf("open GITHUB_OUTPUT %s: %v", path, err)
	}

	var content strings.Builder
	for _, o := range outputs {
		content.WriteString(o.name)
		content.WriteString("=")
		content.WriteString(o.value)
		content.WriteString("\n")
	}
	_, err = file.WriteString(content.String())
	return errors.Join(err, file.Close())
}

func requireEnv(name string) (string, error) {
	value := os.Getenv(name)
	if value == "" {
		return "", fmt.Errorf("%s is not set", name)
	}
	return value, nil
}
