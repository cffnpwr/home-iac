locals {
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

  terraform_netbird_permission_groups = {
    "terraform-plan"  = data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_read
    "terraform-apply" = data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_write
  }

  vultr_terraform_actions = {
    plan = [
      "compute.instance.Read",
      "compute.instance.List",
      "compute.iso.Read",
      "compute.iso.List",
      "network.firewall.Read",
      "network.firewall.List",
    ]
    apply = [
      "compute.instance.*",
      "compute.iso.*",
      "network.firewall.*",
    ]
  }
}

data "cloudflare_account_api_token_permission_groups_list" "terraform_plan" {
  for_each = toset(concat(local.terraform_plan_permission_groups.account, local.terraform_plan_permission_groups.zone))

  account_id = local.cloudflare_account_id
  name       = urlencode(each.key)
}

# NOTE: mainのplan jobでS3 backendのstateの読み取りとCloudflare providerに使うトークン
resource "cloudflare_account_token" "terraform_plan" {
  account_id = local.cloudflare_account_id
  name       = "${local.cloudflare_account_token_name_prefix}terraform-plan"

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

# NOTE: netbirdplan jobでS3 backendのstateの読み書きに使うトークン
resource "cloudflare_account_token" "terraform_netbird" {
  for_each = local.terraform_netbird_permission_groups

  account_id = local.cloudflare_account_id
  name       = "${local.cloudflare_account_token_name_prefix}terraform-netbird-${trimprefix(each.key, "terraform-")}"

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

# NOTE: vultr_userのpasswordは必須の引数のため生成
resource "random_password" "vultr_terraform" {
  for_each = local.vultr_terraform_actions

  length = 32
}

# NOTE: mainのplan・apply jobがVultr providerとmodules/vultr/scriptsで使うAPIキーのservice user
resource "vultr_user" "terraform" {
  for_each = local.vultr_terraform_actions

  name         = "terraform-${each.key}"
  email        = "vultr-terraform-${each.key}@cffnpwr.dev"
  password     = random_password.vultr_terraform[each.key].result
  api_enabled  = true
  service_user = true
}

resource "vultr_organization_policy" "terraform" {
  for_each = local.vultr_terraform_actions

  name        = "terraform-${each.key}"
  description = "Terraform ${each.key} in CI of cffnpwr/home-iac"

  document {
    version = "2026-03-20"
    statement {
      effect    = "Allow"
      actions   = each.value
      resources = ["*"]
    }
  }
}

resource "vultr_organization_policy_user_attachment" "terraform" {
  for_each = local.vultr_terraform_actions

  policy_id = vultr_organization_policy.terraform[each.key].id
  user_id   = vultr_user.terraform[each.key].id
}
