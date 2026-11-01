locals {
  cloudflare_account_id = "086a84b440e09bc83330fe07f1966f5d"
}

resource "cloudflare_r2_bucket" "tfstate" {
  account_id = local.cloudflare_account_id
  name       = "home-iac-tfstate"

  lifecycle {
    # NOTE: 破棄すると全リソースのstateが失われる
    prevent_destroy = true
  }
}

resource "cloudflare_r2_bucket" "sealed_secrets_keys" {
  account_id = local.cloudflare_account_id
  name       = "home-iac-sealed-secrets-keys"
}

data "cloudflare_account_api_token_permission_groups_list" "r2_bucket_item_write" {
  account_id = local.cloudflare_account_id
  name       = "Workers%20R2%20Storage%20Bucket%20Item%20Write"
}

resource "cloudflare_account_token" "sealed_secrets_backup" {
  account_id = local.cloudflare_account_id
  name       = "sealed-secrets-backup"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_write.result).id
    }]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.cloudflare_account_id}_default_${cloudflare_r2_bucket.sealed_secrets_keys.name}" = "*"
    })
  }]
}

data "cloudflare_account_api_token_permission_groups_list" "r2_bucket_item_read" {
  account_id = local.cloudflare_account_id
  name       = "Workers%20R2%20Storage%20Bucket%20Item%20Read"
}

resource "cloudflare_account_token" "sealed_secrets_reseal" {
  account_id = local.cloudflare_account_id
  name       = "sealed-secrets-reseal"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_read.result).id
    }]
    # NOTE: CIによるS3 backendのstateの読み取り用
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.cloudflare_account_id}_default_${cloudflare_r2_bucket.tfstate.name}" = "*"
    })
  }]
}

resource "cloudflare_account_token" "terraform_ci" {
  # NOTE: CIのplanはstateをロックしない（-lock=false）ため、planには読み取りだけを許可
  for_each = {
    "terraform-plan"  = data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_read
    "terraform-apply" = data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_write
  }

  account_id = local.cloudflare_account_id
  name       = each.key

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(each.value.result).id
    }]
    # NOTE: CIによるS3 backendのstateの読み書き用
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.cloudflare_account_id}_default_${cloudflare_r2_bucket.tfstate.name}" = "*"
    })
  }]
}
