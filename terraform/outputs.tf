output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "sealed_secrets_cert" {
  value = tls_self_signed_cert.sealed_secrets.cert_pem
}

output "sealed_secrets_backup_r2_access_key_id" {
  value = cloudflare_account_token.sealed_secrets_backup.id
}

output "sealed_secrets_backup_r2_secret_access_key" {
  # NOTE: R2のSecret Access KeyはAPIトークンの値のSHA-256ハッシュ値
  value     = sha256(cloudflare_account_token.sealed_secrets_backup.value)
  sensitive = true
}
