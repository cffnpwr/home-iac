locals {
  talos_machine_secrets = var.talos_machine_secrets

  talos_client_configuration = {
    ca_certificate     = local.talos_machine_secrets.certs.os.cert
    client_certificate = base64encode(tls_locally_signed_cert.talos_client.cert_pem)
    client_key         = base64encode(tls_private_key.talos_client.private_key_pem)
  }
}

# NOTE: bootstrapから受け取るのはmachine_secretsだけのため、Talos APIのクライアント証明書はmachine secretsのCAでmainが発行
resource "tls_private_key" "talos_client" {
  algorithm = "ED25519"
}

resource "tls_cert_request" "talos_client" {
  private_key_pem = tls_private_key.talos_client.private_key_pem

  subject {
    # NOTE: Talos APIは証明書のOrganizationをロールとして扱う
    organization = "os:admin"
  }
}

# NOTE: 証明書の更新はscheduleのapplyがearly_renewal_hoursの期間内に行なう
#       terminate_nodeのactionはtalosconfigを設定に含むため、更新と同じapplyでVultrのインスタンスを置換すると設定が未確定になりエラーになる
#       このため証明書の更新とVultrのインスタンスの置換は別のapplyで行なう
resource "tls_locally_signed_cert" "talos_client" {
  cert_request_pem = tls_cert_request.talos_client.cert_request_pem
  ca_cert_pem      = base64decode(local.talos_machine_secrets.certs.os.cert)
  # NOTE: tls providerはED25519 PRIVATE KEYのPEMを読めないため、鍵の本文の形式（PKCS#8）に合わせてPRIVATE KEYに変える
  #       CAの鍵をstateに保存しないようwrite-onlyの属性で渡す
  ca_private_key_pem_wo         = replace(base64decode(local.talos_machine_secrets.certs.os.key), "ED25519 PRIVATE KEY", "PRIVATE KEY")
  ca_private_key_pem_wo_version = 1

  validity_period_hours = 8760
  early_renewal_hours   = 720
  # NOTE: server_authを含む証明書はTalosのapidのクライアント証明書の検証を通らない
  allowed_uses = ["digital_signature", "client_auth"]
}
