package main

import (
	"errors"
	"flag"
	"fmt"
	"os"

	"github.com/cffnpwr/home-iac/terraform/bootstrap/scripts/internal/ssecustomerkey"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	fs := flag.NewFlagSet("generate-sse-customer-key", flag.ContinueOnError)
	repoRoot := fs.String("repo-root", "", "path to the root of the repository")
	fs.Usage = func() {
		fmt.Fprintln(fs.Output(), "usage: generate-sse-customer-key --repo-root <path>")
		fs.PrintDefaults()
	}
	if err := fs.Parse(os.Args[1:]); err != nil {
		return err
	}
	if *repoRoot == "" || fs.NArg() > 0 {
		fs.Usage()
		return errors.New("--repo-root is required and no positional arguments are accepted")
	}

	keyPath, err := ssecustomerkey.Generate(*repoRoot)
	if err != nil {
		return err
	}
	fmt.Fprintf(os.Stdout, "wrote %s\n", keyPath)
	return nil
}
