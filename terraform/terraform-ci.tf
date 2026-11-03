locals {
  # NOTE: planは変更を適用しないため、planには読み取りだけを許可
  terraform_ci_permission_groups = {
    "terraform-plan" = {
      # NOTE: CIのplanはstateをロックしない（-lock=false）ため、stateも読み取りだけを許可
      tfstate = ["Workers R2 Storage Bucket Item Read"]
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
    # NOTE: applyのCloudflare providerは、トークンの管理にAccount API Tokens Writeが必要
    #       APIトークンで作成したトークンにはこの権限を付けられないため、ダッシュボードで作成したトークンを使う
    "terraform-apply" = {
      tfstate = ["Workers R2 Storage Bucket Item Write"]
      account = []
      zone    = []
    }
  }
}

data "cloudflare_account_api_token_permission_groups_list" "terraform_ci" {
  for_each = toset(flatten([
    for groups in values(local.terraform_ci_permission_groups) : concat(groups.tfstate, groups.account, groups.zone)
  ]))

  account_id = local.cloudflare_account_id
  name       = urlencode(each.key)
}

# NOTE: CIがS3 backendのstateの読み書きと、planのCloudflare providerに使うトークン
resource "cloudflare_account_token" "terraform_ci" {
  for_each = local.terraform_ci_permission_groups

  account_id = local.cloudflare_account_id
  name       = each.key

  policies = [for policy in [
    {
      effect = "allow"
      permission_groups = [
        for name in each.value.tfstate : { id = one(data.cloudflare_account_api_token_permission_groups_list.terraform_ci[name].result).id }
      ]
      resources = jsonencode({
        "com.cloudflare.edge.r2.bucket.${local.cloudflare_account_id}_default_${cloudflare_r2_bucket.tfstate.name}" = "*"
      })
    },
    {
      effect = "allow"
      permission_groups = [
        for name in each.value.account : { id = one(data.cloudflare_account_api_token_permission_groups_list.terraform_ci[name].result).id }
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.${local.cloudflare_account_id}" = "*"
      })
    },
    {
      effect = "allow"
      permission_groups = [
        for name in each.value.zone : { id = one(data.cloudflare_account_api_token_permission_groups_list.terraform_ci[name].result).id }
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.cffnpwr_dev.zone_id}" = "*"
      })
    },
  ] : policy if length(policy.permission_groups) > 0]
}
