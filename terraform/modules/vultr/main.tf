locals {
  any_subnets = {
    v4 = "0.0.0.0"
    v6 = "::"
  }
}

resource "talos_image_factory_schematic" "this" {}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "vultr"
}

data "talos_machine_configuration" "this" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = var.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches = concat(var.config_patches, [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = { "$patch" = "delete" }
      hostname   = var.hostname
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeNodeConfig"
      taints     = var.node_taints
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UnattendedInstallConfig"
      installer = {
        image = data.talos_image_factory_urls.this.urls.installer
      }
      provisioning = {
        diskSelector = {
          # NOTE: 起動に使うISOもディスクとして列挙される
          match = "disk.transport == \"virtio\" && !disk.cdrom"
        }
      }
    }),
  ])
}

# NOTE: VultrはISOの登録時にImage Factoryのリダイレクトをたどれないためリダイレクト先を渡す
data "external" "iso_url" {
  program = ["bun", "${path.module}/scripts/resolve-redirect.ts"]
  query = {
    url = data.talos_image_factory_urls.this.urls.iso
  }
}

resource "terraform_data" "iso_source" {
  input = data.talos_image_factory_urls.this.urls.iso
}

resource "vultr_iso_private" "this" {
  url = data.external.iso_url.result.url

  lifecycle {
    # NOTE: リダイレクト先は有効期限付きの署名付きURLで実行ごとに変わるため、Image FactoryのURLが変わったときだけ作り直す
    ignore_changes       = [url]
    replace_triggered_by = [terraform_data.iso_source]
  }
}

resource "vultr_firewall_group" "this" {}

resource "vultr_firewall_rule" "inbound" {
  for_each = {
    for pair in setproduct(keys(var.inbound_rules), keys(local.any_subnets)) :
    "${pair[0]}_${pair[1]}" => {
      protocol = var.inbound_rules[pair[0]].protocol
      port     = var.inbound_rules[pair[0]].port
      ip_type  = pair[1]
      subnet   = local.any_subnets[pair[1]]
    }
  }

  firewall_group_id = vultr_firewall_group.this.id
  protocol          = each.value.protocol
  port              = each.value.port
  ip_type           = each.value.ip_type
  subnet            = each.value.subnet
  subnet_size       = 0
}

resource "vultr_instance" "this" {
  region            = var.region
  plan              = var.plan
  iso_id            = vultr_iso_private.this.id
  firewall_group_id = vultr_firewall_group.this.id
  # NOTE: Talos APIを公開しないため、machine configはapplyせずVultrのuser-dataから読ませる
  user_data = data.talos_machine_configuration.this.machine_configuration
}
