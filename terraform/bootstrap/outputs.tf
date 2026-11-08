# NOTE: mainの変数へはobjectの値を`terraform output -json`で、文字列の値を`terraform output -raw`で渡す
output "talos_machine_secrets" {
  value     = talos_machine_secrets.this.machine_secrets
  sensitive = true
}

output "sealed_secrets_private_key" {
  value     = tls_private_key.sealed_secrets.private_key_pem
  sensitive = true
}

output "sealed_secrets_cert" {
  value = tls_self_signed_cert.sealed_secrets.cert_pem
}

output "sealed_secrets_data_hmac_key" {
  value     = random_bytes.sealed_secrets_data_hmac_key.hex
  sensitive = true
}

output "google_workspace_access_identity_provider_id" {
  value = cloudflare_zero_trust_access_identity_provider.google_workspace.id
}
