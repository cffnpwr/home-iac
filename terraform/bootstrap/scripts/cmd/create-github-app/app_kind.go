package main

import (
	"fmt"
	"strings"
)

type appKind string

const (
	appKindPlan   appKind = "plan"
	appKindApply  appKind = "apply"
	appKindReseal appKind = "reseal"
	appKindBackup appKind = "backup"
)

const (
	accessRead  = "read"
	accessWrite = "write"
)

type appConfig struct {
	name string
	// GitHub Appのmanifestのdefault_permissions
	permissions map[string]string
	// Client IDと秘密鍵の書き込み先
	destination destination
}

var appKinds = []appKind{appKindPlan, appKindApply, appKindReseal, appKindBackup}

func parseAppKind(value string) (appKind, error) {
	for _, k := range appKinds {
		if value == string(k) {
			return k, nil
		}
	}

	names := make([]string, 0, len(appKinds))
	for _, k := range appKinds {
		names = append(names, string(k))
	}
	return "", fmt.Errorf(
		"invalid GitHub App kind %q, expected one of %s",
		value,
		strings.Join(names, ", "),
	)
}

func (k appKind) config() appConfig {
	switch k {
	case appKindPlan:
		// NOTE: planのrefreshでGitHub providerがmainのrootのenvironmentのsecretを取得するためEnvironmentsのread権限が必要
		return appConfig{
			name:        "cffnpwr-home-iac-plan",
			permissions: map[string]string{"metadata": accessRead, "environments": accessRead},
			destination: environmentDestination{name: "terraform-plan", credentialPrefix: "PLAN"},
		}
	case appKindApply:
		return appConfig{
			name: "cffnpwr-home-iac-apply",
			permissions: map[string]string{
				"metadata":     accessRead,
				"environments": accessWrite,
			},
			destination: environmentDestination{name: "terraform-apply", credentialPrefix: "APPLY"},
		}
	case appKindReseal:
		// NOTE: reseal-sealed-secrets.yamlがgit pushでブランチを更新するためContentsのwrite権限が必要
		//       PRを作成するためPull requestsのwrite権限が必要
		return appConfig{
			name: "cffnpwr-home-iac-reseal",
			permissions: map[string]string{
				"contents":      accessWrite,
				"pull_requests": accessWrite,
			},
			destination: environmentDestination{
				name:             "sealed-secrets-reseal",
				credentialPrefix: "RESEAL",
			},
		}
	case appKindBackup:
		// NOTE: 鍵の退避Jobがrepository_dispatchを送信するためContentsのwrite権限が必要
		return appConfig{
			name:        "cffnpwr-home-iac-key-backup",
			permissions: map[string]string{"contents": accessWrite},
			destination: sealedSecretDestination{
				path:      "kubernetes/apps/sealed-secrets-backup/sealed-secrets-backup-github-app.yaml",
				namespace: "sealed-secrets",
				name:      "sealed-secrets-backup-github-app",
			},
		}
	}
	panic(fmt.Sprintf("unreachable GitHub App kind: %q", k))
}
