locals {
  # NOTE: planは変更を適用しないため、planには読み取りだけを許可
  #       applyのCloudflare providerは、トークンの管理にAccount API Tokens Writeが必要
  #       APIトークンで作成したトークンにはこの権限を付けられないため、applyはダッシュボードで作成したトークンを使う
  terraform_plan_permission_groups = {
    # NOTE: stateの読み取りは、Workers R2 Storage Readで許可
    account = [
      "Access: Apps Read",
      "Access: Organizations, Identity Providers, and Groups Read",
      "Access: Policies Read",
      "Account API Tokens Read",
      "Cloudflare One Connector: cloudflared Read",
      "Email Sending Read",
      "Workers R2 Storage Read",
      "Zero Trust Read",
    ]
    zone = ["DNS Read", "Zone Read"]
  }

  # NOTE: netbirdのrootはCloudflare providerを使わないため、stateの読み書きだけを許可
  #       CIのplanはstateをロックしない（-lock=false）ため、planには読み取りだけを許可
  terraform_netbird_permission_groups = {
    "terraform-plan"  = data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_read
    "terraform-apply" = data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_write
  }
}

data "cloudflare_account_api_token_permission_groups_list" "terraform_plan" {
  for_each = toset(concat(local.terraform_plan_permission_groups.account, local.terraform_plan_permission_groups.zone))

  account_id = local.cloudflare_account_id
  name       = urlencode(each.key)
}

# NOTE: CIのplanが、S3 backendのstateの読み取りとCloudflare providerに使うトークン
resource "cloudflare_account_token" "terraform_plan" {
  account_id = local.cloudflare_account_id
  name       = "terraform-plan"

  policies = [
    {
      effect = "allow"
      permission_groups = [
        for name in local.terraform_plan_permission_groups.account : { id = one(data.cloudflare_account_api_token_permission_groups_list.terraform_plan[name].result).id }
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.${local.cloudflare_account_id}" = "*"
      })
    },
    {
      effect = "allow"
      permission_groups = [
        for name in local.terraform_plan_permission_groups.zone : { id = one(data.cloudflare_account_api_token_permission_groups_list.terraform_plan[name].result).id }
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.cffnpwr_dev.zone_id}" = "*"
      })
    },
  ]
}

moved {
  from = cloudflare_account_token.terraform_ci["terraform-plan"]
  to   = cloudflare_account_token.terraform_plan
}

# NOTE: CIのnetbirdのrootが、S3 backendのstateの読み書きに使うトークン
resource "cloudflare_account_token" "terraform_netbird" {
  for_each = local.terraform_netbird_permission_groups

  account_id = local.cloudflare_account_id
  name       = "terraform-netbird-${trimprefix(each.key, "terraform-")}"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(each.value.result).id
    }]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.cloudflare_account_id}_default_${cloudflare_r2_bucket.tfstate.name}" = "*"
    })
  }]
}

moved {
  from = cloudflare_account_token.terraform_ci["terraform-apply"]
  to   = cloudflare_account_token.terraform_netbird["terraform-apply"]
}
