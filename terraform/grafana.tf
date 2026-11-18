locals {
  grafana_hostname            = "grafana.${data.cloudflare_zone.cffnpwr_dev.name}"
  grafana_access_redirect_uri = "https://${local.grafana_hostname}/login/generic_oauth"
}

resource "cloudflare_zero_trust_access_policy" "grafana" {
  account_id = local.cloudflare_account_id
  name       = "grafana"
  decision   = "allow"
  include = [
    {
      oidc = {
        identity_provider_id = cloudflare_zero_trust_access_identity_provider.pocket_id.id
        claim_name           = "groups"
        claim_value          = "app-grafana"
      }
    },
    {
      gsuite = {
        identity_provider_id = var.google_workspace_access_identity_provider_id
        email                = "app-grafana@${data.cloudflare_zone.cffnpwr_dev.name}"
      }
    },
  ]
}

resource "cloudflare_zero_trust_access_application" "grafana" {
  account_id = local.cloudflare_account_id
  name       = "grafana"
  type       = "saas"
  allowed_idps = [
    cloudflare_zero_trust_access_identity_provider.pocket_id.id,
    var.google_workspace_access_identity_provider_id,
  ]
  policies = [{
    id         = cloudflare_zero_trust_access_policy.grafana.id
    precedence = 1
  }]
  saas_app = {
    auth_type     = "oidc"
    redirect_uris = [local.grafana_access_redirect_uri]
    # NOTE: GrafanaのセッションをAccessのrefresh tokenで延長するため
    grant_types = ["authorization_code_with_pkce", "refresh_tokens"]
    # NOTE: Grafanaがgroupsのapp-grafana-adminで管理者ロールを割り当てるため
    scopes = ["openid", "email", "profile", "groups"]
    # NOTE: ID tokenの有効期間はこの値に関係なく5分
    #       Grafanaはaccess tokenとID tokenのどちらかの期限が切れるとrefreshするため、ID tokenより長くしてもrefreshの間隔は変わらない
    #       access tokenが有効な期間を短くするため、ID tokenの有効期間に合わせる
    access_token_lifetime = "5m"
    refresh_token_options = {
      lifetime = "24h"
    }
  }
}

# NOTE: PostgreSQLのWALとベースバックアップ
resource "cloudflare_r2_bucket" "grafana_db" {
  account_id = local.cloudflare_account_id
  name       = "home-iac-grafana-db"
}

resource "cloudflare_account_token" "grafana_db" {
  account_id = local.cloudflare_account_id
  name       = "${local.cloudflare_account_token_name_prefix}grafana-db"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_write.result).id
    }]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.cloudflare_account_id}_default_${cloudflare_r2_bucket.grafana_db.name}" = "*"
    })
  }]
}

# NOTE: GrafanaがSMTPでalertの通知メールを送るときのパスワードとして、Cloudflare API Tokenを作成
resource "cloudflare_account_token" "grafana_smtp" {
  account_id = local.cloudflare_account_id
  name       = "${local.cloudflare_account_token_name_prefix}grafana-smtp"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(data.cloudflare_account_api_token_permission_groups_list.email_sending_write.result).id
    }]
    resources = jsonencode({
      "com.cloudflare.api.account.${local.cloudflare_account_id}" = "*"
    })
  }]
}
