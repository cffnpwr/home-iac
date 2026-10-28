package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/netip"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"text/template"
)

type mode string

const (
	modeRun   mode = "run"
	modeCheck mode = "check"
)

// Keaは制御ソケットのディレクトリの権限が0750より緩いと起動しない
const controlSocketDirMode = 0o750

type options struct {
	mode          mode
	nodeName      string
	labelSelector string
	subnet        netip.Prefix
	templatePath  string
	configPath    string
	controlSocket string
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	opts, err := parseOptions()
	if err != nil {
		return err
	}

	switch opts.mode {
	case modeCheck:
		// startupProbeで、最初の設定の書き出しが完了したかを判定
		if _, statErr := os.Stat(opts.configPath); statErr != nil {
			return fmt.Errorf("configuration is not written yet: %v", statErr)
		}
		return nil
	case modeRun:
		ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
		defer stop()
		return runReconciler(ctx, opts)
	}
	panic(fmt.Sprintf("unreachable mode: %q", opts.mode))
}

func runReconciler(ctx context.Context, opts options) error {
	text, err := os.ReadFile(opts.templatePath)
	if err != nil {
		return fmt.Errorf("failed to read template %s: %v", opts.templatePath, err)
	}
	tmpl, err := template.New(opts.templatePath).Option("missingkey=error").Parse(string(text))
	if err != nil {
		return fmt.Errorf("invalid template %s: %v", opts.templatePath, err)
	}

	controlSocketDir := filepath.Dir(opts.controlSocket)
	if mkdirErr := os.MkdirAll(controlSocketDir, controlSocketDirMode); mkdirErr != nil {
		return fmt.Errorf("failed to create directory %s: %v", controlSocketDir, mkdirErr)
	}
	if chmodErr := os.Chmod(controlSocketDir, controlSocketDirMode); chmodErr != nil {
		return fmt.Errorf("failed to change mode of directory %s: %v", controlSocketDir, chmodErr)
	}

	rc := reconcilerConfig{
		nodeName:      opts.nodeName,
		labelSelector: opts.labelSelector,
		subnet:        opts.subnet,
		template:      tmpl,
		configPath:    opts.configPath,
		controlSocket: opts.controlSocket,
	}
	r, err := newReconciler(rc, slog.New(slog.NewTextHandler(os.Stderr, nil)))
	if err != nil {
		return err
	}

	return r.run(ctx)
}

func parseOptions() (options, error) {
	var opts options
	flag.StringVar(&opts.nodeName, "node-name", "", "name of the node this Pod runs on")
	flag.StringVar(
		&opts.labelSelector,
		"label-selector",
		"",
		"label selector of the nodes running Kea",
	)
	flag.TextVar(&opts.subnet, "subnet", netip.Prefix{}, "IPv4 subnet that Kea serves")
	flag.StringVar(&opts.templatePath, "template", "", "path to the Kea configuration template")
	flag.StringVar(&opts.configPath, "config", "", "path to write the Kea configuration")
	flag.StringVar(&opts.controlSocket, "control-socket", "", "path to the Kea control socket")
	flag.Parse()

	if flag.NArg() != 1 {
		return options{}, fmt.Errorf(
			"invalid number of arguments: %d, expected 1 mode argument",
			flag.NArg(),
		)
	}
	switch selectedMode := mode(flag.Arg(0)); selectedMode {
	case modeRun, modeCheck:
		opts.mode = selectedMode
	default:
		return options{}, fmt.Errorf(
			"invalid mode: %q, expected %q or %q",
			selectedMode,
			modeRun,
			modeCheck,
		)
	}

	required := map[string]string{"config": opts.configPath}
	if opts.mode == modeRun {
		required["node-name"] = opts.nodeName
		required["label-selector"] = opts.labelSelector
		required["template"] = opts.templatePath
		required["control-socket"] = opts.controlSocket
	}
	var errs []error
	for name, value := range required {
		if value == "" {
			errs = append(errs, fmt.Errorf("flag -%s is not set", name))
		}
	}
	if opts.mode == modeRun && !isIPv4Network(opts.subnet) {
		errs = append(errs, fmt.Errorf(
			"invalid flag -subnet: %q, expected an IPv4 network address with prefix length such as 192.168.0.0/23",
			opts.subnet,
		))
	}

	return opts, errors.Join(errs...)
}

func isIPv4Network(subnet netip.Prefix) bool {
	return subnet.Addr().Is4() && subnet == subnet.Masked()
}
