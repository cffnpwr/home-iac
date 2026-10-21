terraform {
  backend "s3" {
    bucket = "home-iac-tfstate"
    key    = "terraform.tfstate"

    # NOTE: R2はAWSではないため、リージョンはauto固定としAWS向けの検証・チェックサムを無効にする。
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true

    use_lockfile = true

    endpoints = {
      s3 = "https://086a84b440e09bc83330fe07f1966f5d.r2.cloudflarestorage.com"
    }
  }
}
