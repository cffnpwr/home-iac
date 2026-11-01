data "talos_image_factory_overlays_versions" "this" {
  talos_version = var.talos_version
  filters = {
    name = "rpi_generic"
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    overlay = {
      image = one(data.talos_image_factory_overlays_versions.this.overlays_info).image
      name  = one(data.talos_image_factory_overlays_versions.this.overlays_info).name
    }
    customization = {
      # NOTE: machine config適用前にTalos APIへ静的IPで到達するための初期ネットワーク。
      # デバイス名を省略すると名前順で最初の非loopbackインターフェースが選ばれ、オンボードEthernetになるとは限らないため、end0を明示する
      extraKernelArgs = [
        "ip=${var.address}::${var.gateway}:${var.prefix_length}::end0::${join(":", var.nameservers)}",
      ]
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  sbc           = "rpi_generic"
}

data "talos_machine_configuration" "this" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = var.machine_secrets
  talos_version      = var.talos_config_version
  kubernetes_version = var.kubernetes_version
  config_patches = concat(var.config_patches, [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "LinkAliasConfig"
      name       = "net0"
      selector = {
        # NOTE: インターフェース名が実機で確定しないため、RPi4オンボードEthernetのドライバ名で選択する
        match = "link.driver == \"bcmgenet\""
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "LinkConfig"
      name       = "net0"
      addresses  = [{ address = "${var.address}/${var.prefix_length}" }]
      routes     = [{ gateway = var.gateway }]
    }),
    yamlencode({
      apiVersion  = "v1alpha1"
      kind        = "ResolverConfig"
      nameservers = [for address in var.nameservers : { address = address }]
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = { "$patch" = "delete" }
      hostname   = var.hostname
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeNodeConfig"
      labels     = var.node_labels
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UnattendedInstallConfig"
      installer = {
        image = data.talos_image_factory_urls.this.urls.installer
      }
      provisioning = {
        diskSelector = {
          match = "disk.transport == \"mmc\""
        }
      }
    }),
  ])
}

resource "talos_machine" "this" {
  client_configuration  = var.client_configuration
  machine_configuration = data.talos_machine_configuration.this.machine_configuration
  node                  = var.address
  endpoint              = var.address
  image                 = data.talos_image_factory_urls.this.urls.installer
  # NOTE: Kubernetesのコンポーネントのイメージはtalos_clusterがupgrade-k8sの手順で更新する
  ignore_kubernetes_upgrade_drift = true
  drain_on_upgrade                = true
  kubeconfig_wo                   = var.kubeconfig
}
