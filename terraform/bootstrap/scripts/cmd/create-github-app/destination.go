package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/google/go-github/v93/github"

	"github.com/cffnpwr/home-iac/terraform/bootstrap/scripts/internal/gh"
	"github.com/cffnpwr/home-iac/terraform/bootstrap/scripts/internal/githubapp"
	"github.com/cffnpwr/home-iac/terraform/bootstrap/scripts/internal/sealedsecret"
)

// Client IDと秘密鍵の書き込み先
//
//sumtype:decl
type destination interface {
	isDestination()
}

// GitHubのenvironmentのvariable・secretに書き込む
type environmentDestination struct {
	// environmentの名前
	name string
	// environmentに登録するvariable・secretの名前の接頭辞
	credentialPrefix string
}

// Client IDと秘密鍵を暗号化したSealedSecretのファイルに書き込む
type sealedSecretDestination struct {
	// リポジトリのルートを起点としたファイルのパス
	path      string
	namespace string
	name      string
}

var errDestinationExists = errors.New("credential of the GitHub App already exists")

func (environmentDestination) isDestination() {}

func (d environmentDestination) clientIDVariableName() string {
	return d.credentialPrefix + "_APP_CLIENT_ID"
}

func (d environmentDestination) privateKeySecretName() string {
	return d.credentialPrefix + "_APP_PRIVATE_KEY"
}

func (sealedSecretDestination) isDestination() {}

// Client IDと秘密鍵の書き込み先を確認
func checkDestination(
	ctx context.Context,
	client *github.Client,
	opts options,
	config appConfig,
) error {
	switch d := config.destination.(type) {
	case environmentDestination:
		return checkEnvironmentDestination(ctx, client, opts, d)
	case sealedSecretDestination:
		return checkSealedSecretDestination(opts, d)
	}
	panic(fmt.Sprintf("unreachable destination: %T", config.destination))
}

func checkEnvironmentDestination(
	ctx context.Context,
	client *github.Client,
	opts options,
	d environmentDestination,
) error {
	_, _, err := client.Repositories.GetEnvironment(ctx, opts.repo.Owner, opts.repo.Name, d.name)
	if err != nil {
		if gh.IsNotFound(err) {
			return fmt.Errorf(
				"environment %q does not exist in %s; terraform/bootstrap creates the environment",
				d.name,
				opts.repo,
			)
		}
		return fmt.Errorf("get environment %q in %s: %v", d.name, opts.repo, err)
	}

	if opts.isForced {
		return nil
	}
	variableName := d.clientIDVariableName()
	_, _, err = client.Actions.GetEnvVariable(
		ctx,
		opts.repo.Owner,
		opts.repo.Name,
		d.name,
		variableName,
	)
	switch {
	case err == nil:
		return fmt.Errorf(
			"%w: variable %s in environment %q; --force overwrites it",
			errDestinationExists,
			variableName,
			d.name,
		)
	case gh.IsNotFound(err):
		return nil
	}
	return fmt.Errorf("get variable %s in environment %q: %v", variableName, d.name, err)
}

func checkSealedSecretDestination(opts options, d sealedSecretDestination) error {
	if _, err := os.Stat(opts.certPath); err != nil {
		return fmt.Errorf("certificate %s for sealing is not readable: %v", opts.certPath, err)
	}
	if opts.isForced {
		return nil
	}

	path := filepath.Join(opts.repoRoot, d.path)
	_, err := os.Stat(path)
	switch {
	case err == nil:
		return fmt.Errorf("%w: %s; --force overwrites it", errDestinationExists, path)
	case errors.Is(err, os.ErrNotExist):
		return nil
	}
	return fmt.Errorf("check %s: %v", path, err)
}

func writeCredential(
	ctx context.Context,
	client *github.Client,
	opts options,
	config appConfig,
	credential githubapp.Credential,
) error {
	switch d := config.destination.(type) {
	case environmentDestination:
		if err := gh.SetEnvironmentVariable(
			ctx,
			client,
			opts.repo,
			d.name,
			d.clientIDVariableName(),
			credential.ClientID,
		); err != nil {
			return err
		}
		return gh.SetEnvironmentSecret(
			ctx,
			client,
			opts.repo,
			d.name,
			d.privateKeySecretName(),
			credential.PrivateKeyPEM,
		)
	case sealedSecretDestination:
		return sealedsecret.Write(
			sealedsecret.Target{
				CertPath:  opts.certPath,
				RepoRoot:  opts.repoRoot,
				Path:      d.path,
				Namespace: d.namespace,
				Name:      d.name,
			},
			map[string][]byte{
				"client-id":   []byte(credential.ClientID),
				"private-key": credential.PrivateKeyPEM,
			},
		)
	}
	panic(fmt.Sprintf("unreachable destination: %T", config.destination))
}
