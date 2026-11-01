locals {
  iso_url   = var.secure_boot ? data.talos_image_factory_urls.this.urls.iso_secureboot : data.talos_image_factory_urls.this.urls.iso
  installer = var.secure_boot ? data.talos_image_factory_urls.this.urls.installer_secureboot : data.talos_image_factory_urls.this.urls.installer
}

data "talos_image_factory_extensions_versions" "this" {
  talos_version = var.talos_version
  exact_filters = {
    names = var.extensions
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = merge({
      # NOTE: machine config適用前にTalos APIへ静的IPで到達するための初期ネットワーク。
      #       デバイス名を省略すると名前順で最初の非loopbackインターフェースが選ばれ、bond0等の仮想インターフェースになるため明示
      extraKernelArgs = [
        "ip=${var.address}::${var.gateway}:${var.prefix_length}::${var.link_name}::${join(":", var.nameservers)}",
      ]
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info[*].name
      }
      }, {
      # NOTE: 鍵は初回の起動時にISOのブートメニューから手動で登録。
      #       Sidero Labsの鍵に加えて既知のUEFIの証明書も登録し、それらで署名されたOption ROM等も起動可能にする。
      #       Secure Bootを使わない場合はschematicに含めず、schematicのIDを変えない
      for key, value in { secureboot = { includeWellKnownCertificates = true } } : key => value if var.secure_boot
    })
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "metal"
  architecture  = "amd64"
}

data "talos_machine_configuration" "this" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = var.machine_type
  machine_secrets    = var.machine_secrets
  talos_version      = var.talos_config_version
  kubernetes_version = var.kubernetes_version
  config_patches = concat(var.config_patches, [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "LinkAliasConfig"
      name       = "net0"
      selector = {
        # NOTE: インターフェース名が実機で確定しないため、ドライバ名で選択
        match = "link.driver == \"${var.link_driver}\""
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
        image = local.installer
      }
      provisioning = {
        diskSelector = {
          match = var.install_disk_selector
        }
      }
    }),
    # NOTE: VolumeConfig・UserVolumeConfig・RawVolumeConfigは未作成のボリュームにだけ適用されるため、初回の適用に含める。
    #       EPHEMERALが先に作られ、maxSizeのないユーザーボリューム・raw volumeが残りの領域を使用
    ], var.ephemeral_disk_selector == null && var.ephemeral_max_size == null ? [] : [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "VolumeConfig"
      name       = "EPHEMERAL"
      provisioning = {
        for key, value in {
          diskSelector = var.ephemeral_disk_selector == null ? null : { match = var.ephemeral_disk_selector }
          maxSize      = var.ephemeral_max_size
        } : key => value if value != null
      }
    }),
    ], var.local_path_min_size == null ? [] : [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UserVolumeConfig"
      name       = "local-path-provisioner"
      volumeType = "partition"
      provisioning = {
        diskSelector = {
          match = "system_disk"
        }
        # NOTE: local-path-privisionerのボリュームに割り当てる最小のサイズ
        minSize = var.local_path_min_size
        grow    = true
      }
    }),
    ], var.ceph_osd == null ? [] : [
    # NOTE: RookがOSDに使う、フォーマットしないパーティション。パーティションのラベルはr-ceph-osd
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "RawVolumeConfig"
      name       = "ceph-osd"
      provisioning = {
        for key, value in {
          diskSelector = { match = var.ceph_osd.disk_selector }
          minSize      = var.ceph_osd.min_size
          maxSize      = var.ceph_osd.max_size
          grow         = true
        } : key => value if value != null
      }
    }),
  ])
}

resource "talos_machine" "this" {
  client_configuration  = var.client_configuration
  machine_configuration = data.talos_machine_configuration.this.machine_configuration
  # NOTE: maintenanceモードの初回適用ではノードへ直接接続する必要があるため、endpointを省略してnodeへ接続
  node  = var.address
  image = local.installer
  # NOTE: Kubernetesのコンポーネントのイメージはtalos_clusterがupgrade-k8sの手順で更新
  ignore_kubernetes_upgrade_drift = true
  drain_on_upgrade                = true
  kubeconfig_wo                   = var.kubeconfig
}
