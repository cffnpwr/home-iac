output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "sealed_secrets_cert" {
  value = tls_self_signed_cert.sealed_secrets.cert_pem
}

# NOTE: sealed_secretsの属性名は、各SealedSecretのファイルのパスを、リポジトリルートからの相対パスで表したもの
output "sealed_secrets" {
  value = {
    "kubernetes/apps/sealed-secrets-backup/sealed-secrets-backup-r2.yaml" = {
      namespace = "sealed-secrets"
      name      = "sealed-secrets-backup-r2"
      data = {
        access-key-id = cloudflare_account_token.sealed_secrets_backup.id
        # NOTE: R2のSecret Access Keyは、APIトークンの値をSHA-256でハッシュ化した値を使用
        secret-access-key = sha256(cloudflare_account_token.sealed_secrets_backup.value)
      }
    }
    "kubernetes/apps/sealed-secrets-backup/sealed-secrets-backup-github-app.yaml" = {
      namespace = "sealed-secrets"
      name      = "sealed-secrets-backup-github-app"
      data = {
        client-id   = var.github_app_client_id
        private-key = var.github_app_private_key
      }
    }
    "kubernetes/apps/cert-manager-issuers/cloudflare-api-token.yaml" = {
      namespace = "cert-manager"
      name      = "cloudflare-api-token"
      data = {
        api-token = cloudflare_account_token.cert_manager.value
      }
    }
    "kubernetes/apps/netbird/netbird-cloudflare.yaml" = {
      namespace = "netbird"
      name      = "netbird-cloudflare"
      data = {
        access-client-id     = cloudflare_zero_trust_access_application.netbird.saas_app.client_id
        access-client-secret = cloudflare_zero_trust_access_application.netbird.saas_app.client_secret
        access-issuer        = "https://${data.cloudflare_zero_trust_organization.this.auth_domain}/cdn-cgi/access/sso/oidc/${cloudflare_zero_trust_access_application.netbird.saas_app.client_id}"
        backup-access-key-id = cloudflare_account_token.netbird_backup.id
        # NOTE: R2のSecret Access Keyは、APIトークンの値をSHA-256でハッシュ化した値を使用
        backup-secret-access-key = sha256(cloudflare_account_token.netbird_backup.value)
      }
    }
    "kubernetes/apps/vaultwarden/vaultwarden-r2.yaml" = {
      namespace = "vaultwarden"
      name      = "vaultwarden-r2"
      data = {
        db-access-key-id = cloudflare_account_token.vaultwarden_db.id
        # NOTE: R2のSecret Access Keyは、APIトークンの値をSHA-256でハッシュ化した値を使用
        db-secret-access-key = sha256(cloudflare_account_token.vaultwarden_db.value)
        data-access-key-id   = cloudflare_account_token.vaultwarden_data.id
        # NOTE: R2のSecret Access Keyは、APIトークンの値をSHA-256でハッシュ化した値を使用
        data-secret-access-key = sha256(cloudflare_account_token.vaultwarden_data.value)
      }
    }
    "kubernetes/apps/vaultwarden/vaultwarden-sso.yaml" = {
      namespace = "vaultwarden"
      name      = "vaultwarden-sso"
      data = {
        sso_authority     = "https://${data.cloudflare_zero_trust_organization.this.auth_domain}/cdn-cgi/access/sso/oidc/${cloudflare_zero_trust_access_application.vaultwarden.saas_app.client_id}"
        sso_client_id     = cloudflare_zero_trust_access_application.vaultwarden.saas_app.client_id
        sso_client_secret = cloudflare_zero_trust_access_application.vaultwarden.saas_app.client_secret
      }
    }
    "kubernetes/apps/cloudflared/cloudflared-tunnel-token.yaml" = {
      namespace = "cloudflared"
      name      = "cloudflared-tunnel-token"
      data = {
        token = data.cloudflare_zero_trust_tunnel_cloudflared_token.home.token
      }
    }
  }
  sensitive = true
}

output "sealed_secrets_data_hmac_key" {
  value     = random_bytes.sealed_secrets_data_hmac_key.hex
  sensitive = true
}

output "server_iso_url" {
  value = module.server.iso_url
}
