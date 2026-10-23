output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "sealed_secrets_cert" {
  value = tls_self_signed_cert.sealed_secrets.cert_pem
}
