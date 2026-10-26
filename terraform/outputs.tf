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
