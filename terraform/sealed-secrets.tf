resource "tls_private_key" "sealed_secrets" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "sealed_secrets" {
  private_key_pem = tls_private_key.sealed_secrets.private_key_pem

  subject {
    common_name  = "sealed-secret"
    organization = "sealed-secret"
  }

  validity_period_hours = 87600 # 10 years
  allowed_uses          = ["encipher_only"]
  is_ca_certificate     = true
}
