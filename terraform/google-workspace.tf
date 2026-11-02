resource "cloudflare_dns_record" "google_workspace_mx" {
  zone_id  = data.cloudflare_zone.cffnpwr_dev.zone_id
  name     = data.cloudflare_zone.cffnpwr_dev.name
  type     = "MX"
  content  = "smtp.google.com"
  priority = 1
  ttl      = 1
}

resource "cloudflare_dns_record" "google_workspace_spf" {
  zone_id = data.cloudflare_zone.cffnpwr_dev.zone_id
  name    = data.cloudflare_zone.cffnpwr_dev.name
  type    = "TXT"
  # NOTE: 引用符のないTXTの内容はCloudflareが引用符を付けて保存するため、差分が出ないよう引用符を含める
  content = "\"v=spf1 include:_spf.google.com ~all\""
  ttl     = 1
}

resource "cloudflare_dns_record" "google_workspace_site_verification" {
  zone_id = data.cloudflare_zone.cffnpwr_dev.zone_id
  name    = data.cloudflare_zone.cffnpwr_dev.name
  type    = "TXT"
  content = "\"google-site-verification=b5Bg8dJQzZJSukTBtkX7hUwLydR1Wg5dokDVIUxDF-w\""
  ttl     = 1
}

resource "cloudflare_dns_record" "google_workspace_dkim" {
  zone_id = data.cloudflare_zone.cffnpwr_dev.zone_id
  name    = "google._domainkey.${data.cloudflare_zone.cffnpwr_dev.name}"
  type    = "TXT"
  # NOTE: Cloudflareは255文字を超えるTXTの内容を255文字ごとの文字列に分割して保存するため、差分が出ないよう同じ位置で分割する
  content = join(" ", [
    "\"v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAggQ2+kYvhZC92i9xjrtmQPGHDeaypD1qCY0eXvlDvW8cw0oeLPydvceEtTOvVLEcaPqyu/2fNzAtRqekFfvR2vO0ak5OrO8oD76Uw6YTBNZo83YwcefWCI3qXpOgd/8cFrYtG2Q+JsfSrKgG72GK5bPwtGp6SHAl7FzmVO/aI8xrdJLmIdVLvPWCDaBeyu6to\"",
    "\"sK7ZzSRRV/MK3WkSLb0LH0rkoyd5HMvzqRlASgYohV/kpO8mzFfnHeYgK74c0B/u0oYUC9NnxUudz32y4dkDHSdvMwfW/Y2Wclt42BdF/0T1SWdyfPy6Q2Ml4cc0aOSvYpShwZqOVgSylsyYV74zwIDAQAB\"",
  ])
  ttl = 1
}

resource "cloudflare_dns_record" "dmarc" {
  zone_id = data.cloudflare_zone.cffnpwr_dev.zone_id
  name    = "_dmarc.${data.cloudflare_zone.cffnpwr_dev.name}"
  type    = "TXT"
  content = "\"v=DMARC1; p=none; rua=mailto:3c43f6a9a5924a3a83dec8855cba96d5@dmarc-reports.cloudflare.net\""
  ttl     = 1
}
