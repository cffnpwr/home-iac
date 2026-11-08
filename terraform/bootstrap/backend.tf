terraform {
  backend "s3" {
    # NOTE: main・netbirdのstateと同じバケットに保存する。plan・resealのトークンはこのバケットを読めるがSSE-Cの鍵が無いと取得できない
    bucket = "home-iac-tfstate"
    key    = "bootstrap.tfstate"

    # NOTE: リージョンはauto固定としAWS向けの検証・チェックサムを無効化
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true

    use_lockfile = true
    # NOTE: SSE-Cの鍵はAWS_SSE_CUSTOMER_KEY環境変数で指定
    encrypt = true

    endpoints = {
      s3 = "https://086a84b440e09bc83330fe07f1966f5d.r2.cloudflarestorage.com"
    }
  }
}
