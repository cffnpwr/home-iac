package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/cli/browser"
	"github.com/google/go-github/v93/github"

	"github.com/cffnpwr/home-iac/terraform/bootstrap/scripts/internal/gh"
	"github.com/cffnpwr/home-iac/terraform/bootstrap/scripts/internal/githubapp"
	"github.com/cffnpwr/home-iac/terraform/bootstrap/scripts/internal/manifest"
)

const (
	homepageURL = "https://github.com/cffnpwr/home-iac"
	maxPort     = 65535
)

type options struct {
	appKind  appKind
	repo     gh.Repository
	isForced bool
	// SealedSecretの暗号化に使う証明書のパス
	certPath string
	// リポジトリのルートのパス
	repoRoot string
	// manifest flowで待ち受けるポート
	listenPort int
}

// app-manifestsのconversionsの応答から使う項目
type convertedApp struct {
	ID       int64
	Slug     string
	ClientID string
	PEM      string
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
	config := opts.appKind.config()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	client, err := gh.NewAPIClient()
	if err != nil {
		return err
	}

	if err = checkDestination(ctx, client, opts, config); err != nil {
		return err
	}

	app, err := registerApp(ctx, client, opts, config)
	if err != nil {
		return err
	}

	openPage(
		"install the GitHub App on "+opts.repo.String(),
		"https://github.com/apps/"+app.Slug+"/installations/new",
	)
	credential := githubapp.Credential{
		AppID:         app.ID,
		ClientID:      app.ClientID,
		PrivateKeyPEM: []byte(app.PEM),
	}
	if err = githubapp.WaitInstallation(
		ctx,
		credential,
		opts.repo.Owner,
		opts.repo.Name,
	); err != nil {
		return err
	}

	if err = writeCredential(ctx, client, opts, config, credential); err != nil {
		return err
	}

	fmt.Fprintf(os.Stdout, "slug: %s\nApp ID: %d\nClient ID: %s\n", app.Slug, app.ID, app.ClientID)
	return nil
}

func parseOptions(args []string) (options, error) {
	fs := flag.NewFlagSet("create-github-app", flag.ContinueOnError)
	owner := fs.String("owner", "cffnpwr", "owner of the repository")
	repo := fs.String("repo", "home-iac", "name of the repository")
	isForced := fs.Bool("force", false, "overwrite the existing credential")
	certPath := fs.String(
		"cert",
		"kubernetes/apps/sealed-secrets/cert.pem",
		"certificate of the sealed-secrets controller to seal the credential for backup, relative to --repo-root unless absolute",
	)
	repoRoot := fs.String("repo-root", "", "path to the root of the repository")
	listenPort := fs.Int(
		"listen-port",
		0,
		"port on 127.0.0.1 to receive the redirect of the manifest flow; the OS chooses a free port if omitted",
	)
	fs.Usage = func() {
		fmt.Fprintln(fs.Output(), "usage: create-github-app [flags] plan|apply|reseal|backup")
		fs.PrintDefaults()
	}

	// NOTE: flagは最初の位置引数で解析を止めるため位置引数の後のフラグも解析する
	if err := fs.Parse(args); err != nil {
		return options{}, err
	}
	positionalArgs := fs.Args()
	if len(positionalArgs) > 0 {
		if err := fs.Parse(positionalArgs[1:]); err != nil {
			return options{}, err
		}
	}
	if len(positionalArgs) == 0 || fs.NArg() > 0 {
		fs.Usage()
		return options{}, errors.New("exactly one GitHub App kind is required")
	}
	if *repoRoot == "" {
		fs.Usage()
		return options{}, errors.New("--repo-root is required")
	}
	if err := validateListenPort(fs, *listenPort); err != nil {
		return options{}, err
	}

	selectedAppKind, err := parseAppKind(positionalArgs[0])
	if err != nil {
		return options{}, err
	}
	return options{
		appKind:    selectedAppKind,
		repo:       gh.Repository{Owner: *owner, Name: *repo},
		isForced:   *isForced,
		certPath:   resolvePath(*repoRoot, *certPath),
		repoRoot:   *repoRoot,
		listenPort: *listenPort,
	}, nil
}

// NOTE: --listen-portを省略した場合はOSが空いているポートを選ぶ
//
//	0を指定した場合も省略と同じ動作になり指定する意味が無いため、1以上のポートだけを受け付ける
func validateListenPort(fs *flag.FlagSet, port int) error {
	isSet := false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "listen-port" {
			isSet = true
		}
	})
	if isSet && (port < 1 || port > maxPort) {
		return fmt.Errorf("--listen-port must be between 1 and %d", maxPort)
	}
	return nil
}

// NOTE: mise run github:create-appはterraform/bootstrap/scriptsで実行するため、相対パスはリポジトリのルートを基準にする
func resolvePath(repoRoot, path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	return filepath.Join(repoRoot, path)
}

// manifestからGitHub Appを登録する
func registerApp(
	ctx context.Context,
	client *github.Client,
	opts options,
	config appConfig,
) (convertedApp, error) {
	newAppURL, err := resolveNewAppURL(ctx, client, opts.repo.Owner)
	if err != nil {
		return convertedApp{}, err
	}

	flow := manifest.Flow{
		NewAppURL: newAppURL,
		Manifest: manifest.Manifest{
			Name:               config.name,
			URL:                homepageURL,
			HookAttributes:     manifest.HookAttributes{URL: homepageURL, Active: false},
			Public:             false,
			DefaultPermissions: config.permissions,
			DefaultEvents:      []string{},
		},
		OnListening: func(pageURL string) { openPage("register the GitHub App", pageURL) },
		ListenPort:  opts.listenPort,
	}
	code, err := flow.Run(ctx)
	if err != nil {
		return convertedApp{}, err
	}

	return convertManifest(ctx, client, code)
}

func resolveNewAppURL(ctx context.Context, client *github.Client, owner string) (string, error) {
	ownerAccount, _, err := client.Users.Get(ctx, owner)
	if err != nil {
		return "", fmt.Errorf("get account %s: %v", owner, err)
	}

	if ownerAccount.GetType() == "Organization" {
		return "https://github.com/organizations/" + owner + "/settings/apps/new", nil
	}
	return "https://github.com/settings/apps/new", nil
}

func convertManifest(
	ctx context.Context,
	client *github.Client,
	code string,
) (convertedApp, error) {
	app, _, err := client.Apps.CompleteAppManifest(ctx, code)
	if err != nil {
		return convertedApp{}, fmt.Errorf("create the GitHub App from the manifest: %v", err)
	}
	return convertedApp{
		ID:       app.GetID(),
		Slug:     app.GetSlug(),
		ClientID: app.GetClientID(),
		PEM:      app.GetPEM(),
	}, nil
}

func openPage(action, url string) {
	fmt.Fprintf(os.Stderr, "Open the following URL in a browser to %s:\n%s\n", action, url)

	// NOTE: 非GUI環境ではブラウザを開けないため、失敗してもエラーにせず案内だけを表示する
	browser.Stdout = io.Discard
	browser.Stderr = io.Discard
	if err := browser.OpenURL(url); err != nil {
		fmt.Fprintln(os.Stderr, "Could not open a browser automatically.")
	}
}
