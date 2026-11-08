package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/cffnpwr/home-iac/terraform/scripts/r2"

	"github.com/cffnpwr/home-iac/terraform/bootstrap/scripts/internal/ssecustomerkey"
)

const (
	cloudflareAccountID = "086a84b440e09bc83330fe07f1966f5d"
	// リポジトリのルートからの、bootstrapのrootのパス
	bootstrapRoot = "terraform/bootstrap"
)

type options struct {
	repoRoot      string
	terraformArgs []string
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	opts, err := parseOptions(os.Args[1:])
	if err != nil {
		return err
	}

	apiToken := os.Getenv("CLOUDFLARE_API_TOKEN")
	if apiToken == "" {
		return errors.New("CLOUDFLARE_API_TOKEN is not set")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// NOTE: S3 backendの認証情報はCLOUDFLARE_API_TOKENのトークンから作る
	credentials, err := r2.NewCredentials(ctx, cloudflareAccountID, apiToken)
	if err != nil {
		return err
	}
	if err = setEnv(map[string]string{
		"AWS_ACCESS_KEY_ID":     credentials.AccessKeyID,
		"AWS_SECRET_ACCESS_KEY": credentials.SecretAccessKey,
	}); err != nil {
		return err
	}

	if os.Getenv("AWS_SSE_CUSTOMER_KEY") == "" {
		key, decryptErr := decryptSSECustomerKey(opts.repoRoot)
		if decryptErr != nil {
			return decryptErr
		}
		if err = setEnv(map[string]string{"AWS_SSE_CUSTOMER_KEY": key}); err != nil {
			return err
		}
	}

	terraformPath, err := exec.LookPath("terraform")
	if err != nil {
		return fmt.Errorf("find terraform: %v", err)
	}
	argv := append(
		[]string{"terraform", "-chdir=" + filepath.Join(opts.repoRoot, bootstrapRoot)},
		opts.terraformArgs...,
	)
	// NOTE: 標準入出力・シグナルをterraformが直接扱うためプロセスをterraformに置き換える
	if err = syscall.Exec(terraformPath, argv, os.Environ()); err != nil {
		return fmt.Errorf("exec %s: %v", terraformPath, err)
	}
	return nil
}

func parseOptions(args []string) (options, error) {
	fs := flag.NewFlagSet("tf", flag.ContinueOnError)
	repoRoot := fs.String("repo-root", "", "path to the root of the repository")
	fs.Usage = func() {
		fmt.Fprintln(fs.Output(), "usage: tf --repo-root <path> [--] [terraform arguments...]")
		fs.PrintDefaults()
	}

	// NOTE: flagは最初の位置引数か--で解析を止めるため以降の引数をterraformの引数として渡す
	if err := fs.Parse(args); err != nil {
		return options{}, err
	}
	if *repoRoot == "" {
		fs.Usage()
		return options{}, errors.New("--repo-root is required")
	}
	return options{repoRoot: *repoRoot, terraformArgs: fs.Args()}, nil
}

func decryptSSECustomerKey(repoRoot string) (string, error) {
	keyPath := filepath.Join(repoRoot, ssecustomerkey.Path)
	if _, err := os.Stat(keyPath); err != nil {
		return "", fmt.Errorf(
			"AWS_SSE_CUSTOMER_KEY is not set and %s is not readable: %v",
			keyPath,
			err,
		)
	}
	identityPath := os.Getenv("AGE_IDENTITY_FILE")
	if identityPath == "" {
		return "", errors.New("AWS_SSE_CUSTOMER_KEY and AGE_IDENTITY_FILE are not set")
	}
	// NOTE: mise run tf:bootstrapはterraform/bootstrap/scriptsで実行するため、相対パスはリポジトリのルートを基準にする
	if !filepath.IsAbs(identityPath) {
		identityPath = filepath.Join(repoRoot, identityPath)
	}

	return ssecustomerkey.Decrypt(repoRoot, identityPath)
}

func setEnv(values map[string]string) error {
	for name, value := range values {
		if err := os.Setenv(name, value); err != nil {
			return fmt.Errorf("set %s: %v", name, err)
		}
	}
	return nil
}
