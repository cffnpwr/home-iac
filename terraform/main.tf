locals {
  talos_cluster_name     = "cffnpwr-home"
  rpi4_address           = "192.168.0.129"
  talos_cluster_endpoint = "https://${local.rpi4_address}:6443"

  home_gateway_address      = "192.168.0.1"
  home_subnet_prefix_length = 23
  nameservers               = ["1.1.1.1", "1.0.0.1"]

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

resource "talos_machine_secrets" "this" {
  talos_version = local.talos_config_version
}

data "talos_client_configuration" "this" {
  cluster_name         = local.talos_cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [local.rpi4_address]
  nodes                = [local.rpi4_address]
}

# NOTE: Talosのアップグレードの前にノードをdrainするためのkubeconfig。stateに残さないようephemeralで生成
ephemeral "talos_cluster_kubeconfig" "this" {
  cluster_name    = local.talos_cluster_name
  endpoint        = local.talos_cluster_endpoint
  machine_secrets = talos_machine_secrets.this.machine_secrets
}

resource "talos_cluster" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
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
    cert_pem        = tls_self_signed_cert.sealed_secrets.cert_pem
    private_key_pem = tls_private_key.sealed_secrets.private_key_pem
  }
}

module "rpi4" {
  source = "./modules/rpi4"

  cluster_name         = local.talos_cluster_name
  cluster_endpoint     = local.talos_cluster_endpoint
  machine_secrets      = talos_machine_secrets.this.machine_secrets
  client_configuration = talos_machine_secrets.this.client_configuration
  talos_version        = local.talos_version
  talos_config_version = local.talos_config_version
  kubernetes_version   = local.kubernetes_version
  kubeconfig           = ephemeral.talos_cluster_kubeconfig.this.kubeconfig_raw
  config_patches       = local.talos_common_config_patches
  inline_manifests     = module.inline_manifests.inline_manifests
  address              = local.rpi4_address
  prefix_length        = local.home_subnet_prefix_length
  gateway              = local.home_gateway_address
  nameservers          = local.nameservers
  hostname             = "cpwr-rpi4"
  node_labels = {
    "topology.kubernetes.io/zone" = "home"
  }
}

module "vultr" {
  source = "./modules/vultr"

  cluster_name         = local.talos_cluster_name
  cluster_endpoint     = local.talos_cluster_endpoint
  machine_secrets      = talos_machine_secrets.this.machine_secrets
  client_configuration = talos_machine_secrets.this.client_configuration
  talos_endpoint       = local.rpi4_address
  talos_version        = local.talos_version
  talos_config_version = local.talos_config_version
  kubernetes_version   = local.kubernetes_version
  kubeconfig           = ephemeral.talos_cluster_kubeconfig.this.kubeconfig_raw
  config_patches = concat(local.talos_common_config_patches, [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UserVolumeConfig"
      name       = "local-path-provisioner"
      volumeType = "directory"
    }),
  ])
  region          = "nrt"
  plan            = "vc2-2c-4gb"
  hostname_prefix = "cpwr-vltr"
  talosconfig     = data.talos_client_configuration.this.talos_config
  node_labels = {
    "topology.kubernetes.io/zone" = "vultr"
  }
  node_taints = {
    edge = "vultr:NoSchedule"
  }
  inbound_rules = {
    kubespan     = { protocol = "udp", port = "51820" }
    netbird_tls  = { protocol = "tcp", port = "443" }
    netbird_stun = { protocol = "udp", port = "3478" }
  }
}
