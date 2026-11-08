package githubapp

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/bradleyfalzon/ghinstallation/v2"
	"github.com/google/go-github/v93/github"
)

const (
	// インストールの画面の操作を待つ時間
	installationTimeout = 15 * time.Minute
	initialPollInterval = 2 * time.Second
	pollBackoffFactor   = 2
	maxPollInterval     = 30 * time.Second
	requestTimeout      = 30 * time.Second
)

var (
	ErrInvalidPrivateKey   = errors.New("invalid private key of GitHub App")
	ErrInstallationTimeout = errors.New(
		"GitHub App is not installed on the repository before the timeout",
	)
	ErrCheckInstallation = errors.New("check installation of GitHub App failed")
)

type Credential struct {
	AppID         int64
	ClientID      string
	PrivateKeyPEM []byte
}

func WaitInstallation(ctx context.Context, credential Credential, owner, repo string) error {
	// NOTE: ghinstallationはJWTの発行者にClient IDではなくApp IDを使う
	transport, err := ghinstallation.NewAppsTransport(
		http.DefaultTransport,
		credential.AppID,
		credential.PrivateKeyPEM,
	)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrInvalidPrivateKey, err)
	}
	client, err := github.NewClient(
		github.WithTransport(transport),
		github.WithTimeout(requestTimeout),
	)
	if err != nil {
		return fmt.Errorf("%w: create GitHub API client: %v", ErrCheckInstallation, err)
	}

	ctx, cancel := context.WithTimeout(ctx, installationTimeout)
	defer cancel()

	interval := initialPollInterval
	for {
		isInstalled, checkErr := checkInstallation(ctx, client, owner, repo)
		if checkErr != nil {
			return checkErr
		}
		if isInstalled {
			return nil
		}

		select {
		case <-ctx.Done():
			if errors.Is(ctx.Err(), context.DeadlineExceeded) {
				return ErrInstallationTimeout
			}
			return fmt.Errorf("%w: %v", ErrCheckInstallation, ctx.Err())
		case <-time.After(interval):
		}
		interval = min(interval*pollBackoffFactor, maxPollInterval)
	}
}

func checkInstallation(
	ctx context.Context,
	client *github.Client,
	owner, repo string,
) (bool, error) {
	_, _, err := client.Apps.GetRepositoryInstallation(ctx, owner, repo)
	if err == nil {
		return true, nil
	}

	var errorResponse *github.ErrorResponse
	if errors.As(err, &errorResponse) && errorResponse.Response != nil &&
		errorResponse.Response.StatusCode == http.StatusNotFound {
		return false, nil
	}
	return false, fmt.Errorf("%w: %v", ErrCheckInstallation, err)
}
