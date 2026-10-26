package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"reflect"
	"strings"
	"syscall"

	"github.com/go-playground/validator/v10"
	clientconfig "github.com/siderolabs/talos/pkg/machinery/client/config"

	"github.com/cffnpwr/home-iac/terraform/modules/vultr/scripts/internal/kube"
	"github.com/cffnpwr/home-iac/terraform/modules/vultr/scripts/internal/talos"
	"github.com/cffnpwr/home-iac/terraform/modules/vultr/scripts/internal/vultr"
)

type mode string

const (
	modeWaitReady mode = "wait-ready"
	modeDelete    mode = "delete"
	modeDetachIso mode = "detach-iso"
)

type input struct {
	NodeName      string `json:"node_name"      validate:"required"`
	Talosconfig   string `json:"talosconfig"    validate:"required"`
	TalosEndpoint string `json:"talos_endpoint" validate:"required"`
	// detach-isoでのみ使用
	InstanceID  string `json:"instance_id" validate:"required_if=IsDetachIso true"`
	IsDetachIso bool   `json:"-"`
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	selectedMode, err := parseMode()
	if err != nil {
		return err
	}

	in, err := readInput(selectedMode)
	if err != nil {
		return err
	}

	talosconfig, err := clientconfig.FromString(in.Talosconfig)
	if err != nil {
		return fmt.Errorf("invalid talosconfig: %v", err)
	}

	vultrAPIKey := os.Getenv("VULTR_API_KEY")
	if selectedMode == modeDetachIso && vultrAPIKey == "" {
		return errors.New("environment variable VULTR_API_KEY is not set")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cluster, err := connectCluster(ctx, talosconfig, in.TalosEndpoint)
	if err != nil {
		return err
	}

	switch selectedMode {
	case modeWaitReady:
		return waitReady(ctx, cluster, in.NodeName)
	case modeDelete:
		return deleteNode(ctx, cluster, in.NodeName)
	case modeDetachIso:
		return detachIso(ctx, cluster, vultr.NewClient(vultrAPIKey), in.InstanceID, in.NodeName)
	}
	panic(fmt.Sprintf("unreachable mode: %q", selectedMode))
}

func connectCluster(
	ctx context.Context,
	talosconfig *clientconfig.Config,
	talosEndpoint string,
) (*kube.Client, error) {
	kubeconfig, err := talos.FetchKubeconfig(ctx, talosconfig, talosEndpoint)
	if err != nil {
		return nil, err
	}

	return kube.NewClient(kubeconfig)
}

func parseMode() (mode, error) {
	flag.Parse()
	if flag.NArg() != 1 {
		return "", fmt.Errorf(
			"invalid number of arguments: %d, expected 1 mode argument",
			flag.NArg(),
		)
	}

	switch selectedMode := mode(flag.Arg(0)); selectedMode {
	case modeWaitReady, modeDelete, modeDetachIso:
		return selectedMode, nil
	default:
		return "", fmt.Errorf(
			"invalid mode: %q, expected %q, %q or %q",
			selectedMode,
			modeWaitReady,
			modeDelete,
			modeDetachIso,
		)
	}
}

func readInput(selectedMode mode) (input, error) {
	in := input{IsDetachIso: selectedMode == modeDetachIso}
	if err := json.NewDecoder(os.Stdin).Decode(&in); err != nil {
		return input{}, fmt.Errorf("invalid input value: %v", err)
	}

	validate := validator.New(validator.WithRequiredStructEnabled())
	validate.RegisterTagNameFunc(func(field reflect.StructField) string {
		return strings.Split(field.Tag.Get("json"), ",")[0]
	})
	err := validate.Struct(in)
	if err == nil {
		return in, nil
	}

	var fieldErrors validator.ValidationErrors
	if !errors.As(err, &fieldErrors) {
		return input{}, fmt.Errorf("invalid input value: %v", err)
	}

	messages := make([]string, 0, len(fieldErrors))
	for _, fieldError := range fieldErrors {
		messages = append(messages, "input value does not have "+fieldError.Field())
	}

	return input{}, errors.New(strings.Join(messages, "; "))
}
