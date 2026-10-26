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
    "kubernetes/platform/sealed-secrets-backup/sealed-secrets-backup-r2.yaml" = {
      namespace = "sealed-secrets"
      name      = "sealed-secrets-backup-r2"
      data = {
        access-key-id = cloudflare_account_token.sealed_secrets_backup.id
        # NOTE: R2のSecret Access Keyは、APIトークンの値をSHA-256でハッシュ化した値を使用
        secret-access-key = sha256(cloudflare_account_token.sealed_secrets_backup.value)
      }
    }
    "kubernetes/platform/sealed-secrets-backup/sealed-secrets-backup-github-app.yaml" = {
      namespace = "sealed-secrets"
      name      = "sealed-secrets-backup-github-app"
      data = {
        client-id   = var.github_app_client_id
        private-key = var.github_app_private_key
      }
    }
    "kubernetes/platform/cert-manager-issuers/cloudflare-api-token.yaml" = {
      namespace = "cert-manager"
      name      = "cloudflare-api-token"
      data = {
        api-token = cloudflare_account_token.cert_manager.value
      }
    }
    "kubernetes/platform/netbird/netbird-secrets.yaml" = {
      namespace = "netbird"
      name      = "netbird-secrets"
      data = {
        access-client-id                  = cloudflare_zero_trust_access_application.netbird.saas_app.client_id
        access-client-secret              = cloudflare_zero_trust_access_application.netbird.saas_app.client_secret
        access-issuer                     = "https://${data.cloudflare_zero_trust_organization.this.auth_domain}/cdn-cgi/access/sso/oidc/${cloudflare_zero_trust_access_application.netbird.saas_app.client_id}"
        datastore-encryption-key          = random_bytes.netbird_datastore_encryption_key.base64
        relay-auth-secret                 = random_bytes.netbird_relay_auth_secret.hex
        idp-session-cookie-encryption-key = random_bytes.netbird_idp_session_cookie_encryption_key.base64
        placeholder-owner-password-hash   = random_password.netbird_placeholder_owner.bcrypt_hash
        backup-access-key-id              = cloudflare_account_token.netbird_backup.id
        # NOTE: R2のSecret Access Keyは、APIトークンの値をSHA-256でハッシュ化した値を使用
        backup-secret-access-key = sha256(cloudflare_account_token.netbird_backup.value)
      }
    }
    "kubernetes/platform/cloudflared/cloudflared-tunnel-token.yaml" = {
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
