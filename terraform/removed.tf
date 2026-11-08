# NOTE: bootstrapのrootへ移したリソース。移行の手順でstateをbootstrapへ移すため破棄せずに管理の対象から外す
removed {
  from = talos_machine_secrets.this
  lifecycle {
    destroy = false
  }
}

removed {
  from = tls_private_key.sealed_secrets
  lifecycle {
    destroy = false
  }
}

removed {
  from = tls_self_signed_cert.sealed_secrets
  lifecycle {
    destroy = false
  }
}

removed {
  from = random_bytes.sealed_secrets_data_hmac_key
  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_r2_bucket.tfstate
  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_account_token.sealed_secrets_reseal
  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_account_token.terraform_plan
  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_account_token.terraform_netbird
  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_zero_trust_access_identity_provider.google_workspace
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_repository_environment.sealed_secrets_reseal
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_repository_environment.terraform_apply
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_repository_environment.terraform_plan
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_repository_environment_deployment_policy.terraform_apply_main
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_environment_secret.sealed_secrets_reseal_aws_access_key_id
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_environment_secret.sealed_secrets_reseal_aws_secret_access_key
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_environment_secret.terraform_plan_aws_access_key_id
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_environment_secret.terraform_plan_aws_secret_access_key
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_environment_secret.terraform_netbird_aws_access_key_id
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_environment_secret.terraform_netbird_aws_secret_access_key
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_environment_secret.terraform_plan_cloudflare_api_token
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_environment_secret.terraform_apply_cloudflare_api_token
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_environment_secret.terraform_ci_netbird_pat
  lifecycle {
    destroy = false
  }
}

# NOTE: 移行後に使わなくなるリポジトリのシークレット・variable。GitHubからは手作業で削除する
removed {
  from = github_actions_secret.vultr_api_key
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_secret.update_private_key
  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_variable.update_client_id
  lifecycle {
    destroy = false
  }
}
