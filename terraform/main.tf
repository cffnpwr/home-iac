locals {
  talos_cluster_name = "cffnpwr-home"
  # NOTE: control planeが共有するVirtual IP
  talos_cluster_vip      = "192.168.0.128"
  talos_cluster_endpoint = "https://${local.talos_cluster_vip}:6443"

  home_gateway_address      = "192.168.0.1"
  home_subnet_prefix_length = 23
  nameservers               = ["1.1.1.1", "1.0.0.1"]

  rpi4_address = "192.168.0.129"

  talos_common_config_patches = [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeSpanConfig"
      enabled    = true
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ResolverConfig"
      hostDNS = {
        # NOTE: Ciliumのbpf.masqueradeと併用するとCoreDNSが正しく動作しない
        forwardKubeDNSToHost = false
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeletConfig"
      config = {
        # NOTE: metrics-serverがkubeletのサービング証明書を検証できるよう、クラスタのCAで署名された証明書をCSRで要求
        serverTLSBootstrap = true
      }
    }),
  ]

  # NOTE: inline manifestは各control planeが適用するため、全control planeに同じ設定を置く
  talos_controlplane_config_patches = concat([
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeNodeConfig"
      taints = {
        "node-role.kubernetes.io/control-plane" = { "$patch" = "delete" }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeFlannelCNIConfig"
      "$patch"   = "delete"
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeProxyConfig"
      enabled    = false
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeAPIServerConfig"
      extraArgs = {
        # NOTE: ClusterIPではなくEndpointSliceから接続先を選ぶ
        enable-aggregator-routing = "true"
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "Layer2VIPConfig"
      name       = local.talos_cluster_vip
      # NOTE: 各モジュールのLinkAliasConfigがLANのインターフェースに付ける別名
      link = "net0"
    }),
    ], [
    for name, manifest in module.inline_manifests.inline_manifests : yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeInlineManifestConfig"
      name       = name
      manifest   = manifest
    })
  ])

  # NOTE: 自宅LANのサーバー。ホスト名をキーにする
  #       ディスクはCEL式のdisk.wwid・disk.modelで選択し、起動に使うUSBメモリ等を選ばないようにする
  servers = {
    # NOTE: Custom PC
    cpwr-svr1 = {
      address = "192.168.0.130"
      extensions = [
        "siderolabs/intel-ucode",
        "siderolabs/realtek-firmware",
      ]
      link_name               = "enp2s0"
      link_driver             = "r8169"
      install_disk_selector   = "disk.transport == \"nvme\""
      ephemeral_max_size      = "200GiB"
      ephemeral_disk_selector = null
      # NOTE: NVMe（1TB）のEPHEMERAL以外の領域をOSDにする
      ceph_osd = {
        disk_selector = "system_disk"
        min_size      = "100GiB"
        max_size      = null
      }
      secure_boot = true
    }

    # NOTE: Dell Precision Tower 3431
    cpwr-svr2 = {
      address                 = "192.168.0.131"
      extensions              = ["siderolabs/intel-ucode"]
      link_name               = "eno1"
      link_driver             = "e1000e"
      install_disk_selector   = "disk.transport == \"nvme\""
      ephemeral_max_size      = null
      ephemeral_disk_selector = null
      # NOTE: HDD（Seagate ST1000DM010、1TB）
      ceph_osd = {
        disk_selector = "disk.wwid == \"naa.5000c500c4153662\""
        min_size      = null
        max_size      = "100%"
      }
      secure_boot = true
    }

    # NOTE: INVERSENET FRONTIER
    cpwr-svr3 = {
      address = "192.168.0.132"
      extensions = [
        "siderolabs/intel-ucode",
        "siderolabs/realtek-firmware",
      ]
      link_name   = "enp2s0"
      link_driver = "r8169"
      # NOTE: HP S700（250GB）。wwidにモデル名と空白が入るため、モデル名で選択
      install_disk_selector = "disk.model == \"HP SSD S700 250G\""
      ephemeral_max_size    = null
      # NOTE: Crucial MX300（275GB）
      ephemeral_disk_selector = "disk.wwid == \"naa.500a0751144eaf73\""
      # NOTE: HDD（WD20EFRX、2TB）
      ceph_osd = {
        disk_selector = "disk.wwid == \"naa.50014ee2b9f89f48\""
        min_size      = null
        max_size      = "100%"
      }
      secure_boot = true
    }
  }
}

locals {
  # NOTE: 初回導入と以降のArgo CDの同期で描画を揃えるため、chartの指定をApplicationSetのパラメーターから取得
  helm_applications = {
    for name in ["cilium", "argocd"] : name => yamldecode(file("${path.module}/../kubernetes/apps/${name}/app.yaml"))
  }
  helm_charts = {
    for name, app in local.helm_applications : name => {
      repository   = app.chart.repoURL
      chart        = app.chart.name
      version      = app.chart.version
      release_name = app.chart.releaseName
      namespace    = app.namespace
    }
  }
}

data "talos_client_configuration" "this" {
  cluster_name         = local.talos_cluster_name
  client_configuration = local.talos_client_configuration
  # NOTE: Virtual IPはetcdの障害時に使えないため、Talos APIには各control planeのアドレスで接続
  endpoints = concat([local.rpi4_address], [for server in values(local.servers) : server.address])
  nodes     = [local.rpi4_address]
}

# NOTE: Talosのアップグレードの前にノードをdrainするためのkubeconfig。stateに残さないようephemeralで生成
ephemeral "talos_cluster_kubeconfig" "this" {
  cluster_name    = local.talos_cluster_name
  endpoint        = local.talos_cluster_endpoint
  machine_secrets = local.talos_machine_secrets
}

resource "talos_cluster" "this" {
  client_configuration = local.talos_client_configuration
  node                 = local.rpi4_address
  kubernetes_version   = local.kubernetes_version

  depends_on = [module.rpi4]
}

module "inline_manifests" {
  source = "./modules/inline-manifests"

  kubernetes_version = local.kubernetes_version
  cilium_chart = merge(local.helm_charts.cilium, {
    values = file("${path.module}/../kubernetes/apps/cilium/values.yaml")
  })
  argocd_chart = merge(local.helm_charts.argocd, {
    values = file("${path.module}/../kubernetes/apps/argocd/values.yaml")
  })
  argocd_root_application_source = {
    repo_url = "https://github.com/cffnpwr/home-iac.git"
    path     = "kubernetes/apps"
  }
  sealed_secrets_key = {
    cert_pem        = var.sealed_secrets_cert
    private_key_pem = var.sealed_secrets_private_key
  }
}

module "rpi4" {
  source = "./modules/rpi4"

  cluster_name         = local.talos_cluster_name
  cluster_endpoint     = local.talos_cluster_endpoint
  machine_secrets      = local.talos_machine_secrets
  client_configuration = local.talos_client_configuration
  talos_version        = local.talos_version
  talos_config_version = local.talos_config_version
  kubernetes_version   = local.kubernetes_version
  kubeconfig           = ephemeral.talos_cluster_kubeconfig.this.kubeconfig_raw
  config_patches       = concat(local.talos_common_config_patches, local.talos_controlplane_config_patches)
  address              = local.rpi4_address
  prefix_length        = local.home_subnet_prefix_length
  gateway              = local.home_gateway_address
  nameservers          = local.nameservers
  hostname             = "cpwr-rpi4"
  node_labels = {
    "topology.kubernetes.io/zone" = "home"
  }
}

locals {
  server_node_labels = {
    for name, server in local.servers : name => merge(
      {
        "topology.kubernetes.io/zone" = "home"
      },
      # NOTE: CephのOSDを置く永続化用のノードの場合はラベルを付与
      server.ceph_osd == null ? {} : {
        "cffnpwr.dev/storage" = "true"
      },
    )
  }
}

# NOTE: control planeのTalosを1台ずつ更新するため、for_eachを使わずにノードごとにモジュールを呼び出し、upgrade_afterで順序を付ける。
#       同時に更新すると、drain・再起動が重なりetcdのクォーラムを失うおそれがある。
#       for_eachの同じモジュールの呼び出しでは、インスタンス間で参照すると循環参照になるため順序を付けられない
module "cpwr_svr1" {
  source = "./modules/metal-amd64"

  cluster_name            = local.talos_cluster_name
  cluster_endpoint        = local.talos_cluster_endpoint
  machine_secrets         = local.talos_machine_secrets
  client_configuration    = local.talos_client_configuration
  talos_version           = local.talos_version
  talos_config_version    = local.talos_config_version
  kubernetes_version      = local.kubernetes_version
  kubeconfig              = ephemeral.talos_cluster_kubeconfig.this.kubeconfig_raw
  machine_type            = "controlplane"
  config_patches          = concat(local.talos_common_config_patches, local.talos_controlplane_config_patches)
  address                 = local.servers["cpwr-svr1"].address
  prefix_length           = local.home_subnet_prefix_length
  gateway                 = local.home_gateway_address
  nameservers             = local.nameservers
  hostname                = "cpwr-svr1"
  node_labels             = local.server_node_labels["cpwr-svr1"]
  extensions              = local.servers["cpwr-svr1"].extensions
  link_name               = local.servers["cpwr-svr1"].link_name
  link_driver             = local.servers["cpwr-svr1"].link_driver
  install_disk_selector   = local.servers["cpwr-svr1"].install_disk_selector
  ephemeral_max_size      = local.servers["cpwr-svr1"].ephemeral_max_size
  ephemeral_disk_selector = local.servers["cpwr-svr1"].ephemeral_disk_selector
  ceph_osd                = local.servers["cpwr-svr1"].ceph_osd
  secure_boot             = local.servers["cpwr-svr1"].secure_boot

  depends_on = [talos_cluster.this]
}

module "cpwr_svr2" {
  source = "./modules/metal-amd64"

  cluster_name            = local.talos_cluster_name
  cluster_endpoint        = local.talos_cluster_endpoint
  machine_secrets         = local.talos_machine_secrets
  client_configuration    = local.talos_client_configuration
  talos_version           = local.talos_version
  talos_config_version    = local.talos_config_version
  kubernetes_version      = local.kubernetes_version
  kubeconfig              = ephemeral.talos_cluster_kubeconfig.this.kubeconfig_raw
  machine_type            = "controlplane"
  config_patches          = concat(local.talos_common_config_patches, local.talos_controlplane_config_patches)
  address                 = local.servers["cpwr-svr2"].address
  prefix_length           = local.home_subnet_prefix_length
  gateway                 = local.home_gateway_address
  nameservers             = local.nameservers
  hostname                = "cpwr-svr2"
  node_labels             = local.server_node_labels["cpwr-svr2"]
  extensions              = local.servers["cpwr-svr2"].extensions
  link_name               = local.servers["cpwr-svr2"].link_name
  link_driver             = local.servers["cpwr-svr2"].link_driver
  install_disk_selector   = local.servers["cpwr-svr2"].install_disk_selector
  ephemeral_max_size      = local.servers["cpwr-svr2"].ephemeral_max_size
  ephemeral_disk_selector = local.servers["cpwr-svr2"].ephemeral_disk_selector
  ceph_osd                = local.servers["cpwr-svr2"].ceph_osd
  secure_boot             = local.servers["cpwr-svr2"].secure_boot
  upgrade_after           = module.cpwr_svr1.talos_machine_id

  depends_on = [talos_cluster.this]
}

module "cpwr_svr3" {
  source = "./modules/metal-amd64"

  cluster_name            = local.talos_cluster_name
  cluster_endpoint        = local.talos_cluster_endpoint
  machine_secrets         = local.talos_machine_secrets
  client_configuration    = local.talos_client_configuration
  talos_version           = local.talos_version
  talos_config_version    = local.talos_config_version
  kubernetes_version      = local.kubernetes_version
  kubeconfig              = ephemeral.talos_cluster_kubeconfig.this.kubeconfig_raw
  machine_type            = "controlplane"
  config_patches          = concat(local.talos_common_config_patches, local.talos_controlplane_config_patches)
  address                 = local.servers["cpwr-svr3"].address
  prefix_length           = local.home_subnet_prefix_length
  gateway                 = local.home_gateway_address
  nameservers             = local.nameservers
  hostname                = "cpwr-svr3"
  node_labels             = local.server_node_labels["cpwr-svr3"]
  extensions              = local.servers["cpwr-svr3"].extensions
  link_name               = local.servers["cpwr-svr3"].link_name
  link_driver             = local.servers["cpwr-svr3"].link_driver
  install_disk_selector   = local.servers["cpwr-svr3"].install_disk_selector
  ephemeral_max_size      = local.servers["cpwr-svr3"].ephemeral_max_size
  ephemeral_disk_selector = local.servers["cpwr-svr3"].ephemeral_disk_selector
  ceph_osd                = local.servers["cpwr-svr3"].ceph_osd
  secure_boot             = local.servers["cpwr-svr3"].secure_boot
  upgrade_after           = module.cpwr_svr2.talos_machine_id

  depends_on = [talos_cluster.this]
}

module "vultr" {
  source = "./modules/vultr"

  cluster_name         = local.talos_cluster_name
  cluster_endpoint     = local.talos_cluster_endpoint
  machine_secrets      = local.talos_machine_secrets
  client_configuration = local.talos_client_configuration
  talos_endpoint       = local.rpi4_address
  talos_version        = local.talos_version
  talos_config_version = local.talos_config_version
  kubernetes_version   = local.kubernetes_version
  kubeconfig           = ephemeral.talos_cluster_kubeconfig.this.kubeconfig_raw
  config_patches       = local.talos_common_config_patches
  region               = "nrt"
  plan                 = "vc2-2c-4gb"
  hostname_prefix      = "cpwr-vltr"
  talosconfig          = data.talos_client_configuration.this.talos_config
  node_labels = {
    "topology.kubernetes.io/zone" = "vultr"
  }
  node_taints = {}
  inbound_rules = {
    kubespan     = { protocol = "udp", port = "51820" }
    netbird_tls  = { protocol = "tcp", port = "443" }
    netbird_stun = { protocol = "udp", port = "3478" }
  }
}
