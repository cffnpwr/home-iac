locals {
  # NOTE: CIからTerraformのapply・SealedSecretの再暗号化で接続する、Talos APIとkube-apiserverのポート
  ci_cffnpwr_home_lan_ports = ["50000", "6443"]
  ci_environments           = ["terraform-apply", "sealed-secrets-reseal"]
}

resource "netbird_group" "ci" {
  name = "ci"
}

# NOTE: jobの終了後にピアが残らないよう、オフラインが10分を超えたピアを削除するephemeralのキー
resource "netbird_setup_key" "ci" {
  name        = "ci"
  type        = "reusable"
  ephemeral   = true
  auto_groups = [netbird_group.ci.id]
}

# NOTE: 自宅LANのサブネットの宛先とそのグループは、OperatorのNetworkResourceがCIDRを指定できないためダッシュボードで作成
data "netbird_group" "cffnpwr_home_lan" {
  name = "cffnpwr-home-lan"
}

resource "netbird_policy" "ci_cffnpwr_home_lan" {
  name    = "ci-cffnpwr-home-lan"
  enabled = true

  rule {
    name          = "ci-cffnpwr-home-lan"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = local.ci_cffnpwr_home_lan_ports
    sources       = [netbird_group.ci.id]
    destinations  = [data.netbird_group.cffnpwr_home_lan.id]
  }
}

# NOTE: 手元でapply済みのstateにある、変更前の名前のポリシーを引き継ぐ
moved {
  from = netbird_policy.ci_home_lan
  to   = netbird_policy.ci_cffnpwr_home_lan
}

resource "github_actions_environment_secret" "netbird_setup_key" {
  for_each = toset(local.ci_environments)

  repository  = "home-iac"
  environment = each.key
  secret_name = "NETBIRD_SETUP_KEY"
  value       = netbird_setup_key.ci.key
}
