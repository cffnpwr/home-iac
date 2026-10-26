locals {
  any_subnets = {
    v4 = "0.0.0.0"
    v6 = "::"
  }
  hostname = "${var.hostname_prefix}-${random_id.hostname_suffix.hex}"
  # NOTE: 起動に使うISOもディスクとして列挙される
  install_disk_selector = "disk.transport == \"virtio\" && !disk.cdrom"
}

resource "random_id" "hostname_suffix" {
  byte_length = 4
  # NOTE: 以下のいずれかが更新されたときインスタンスを入れ替える
  keepers = {
    node_taints           = jsonencode(var.node_taints)
    installer             = data.talos_image_factory_urls.this.urls.installer
    install_disk_selector = local.install_disk_selector
    region                = var.region
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
      hostname   = local.hostname
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeNodeConfig"
      labels     = var.node_labels
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
          match = local.install_disk_selector
        }
      }
    }),
  ])
}

# NOTE: VultrはISOの登録時にImage Factoryのリダイレクトをたどれないためリダイレクト先を渡す
data "external" "iso_url" {
  program = ["go", "run", "-C", "${path.module}/scripts", "./cmd/resolve-redirect"]
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
  hostname          = local.hostname
  # NOTE: user-dataは初回の起動（インストール）でだけ読まれる。参加後の設定更新はtalos_machine_configuration_applyが担う
  user_data = data.talos_machine_configuration.this.machine_configuration

  lifecycle {
    # NOTE: random_idのkeepersが変わるとホスト名が変わり、新しいインスタンスを作ってから古いインスタンスを消す
    create_before_destroy = true

    # NOTE: create_before_destroyのリソースではdestroy-time provisionerが実行されないため、古いNodeの削除はactionで行う
    action_trigger {
      events  = [before_destroy]
      actions = [action.local_command.delete_node]
    }
  }
}

resource "talos_machine_configuration_apply" "this" {
  client_configuration        = var.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this.machine_configuration
  node                        = vultr_instance.this.main_ip
  # NOTE: Talos APIは公開していないため、control planeのapidがKubeSpan経由で中継する
  endpoint = var.talos_endpoint
  # NOTE: 入れ替えで古いインスタンスを消す前に、古いノードをcordon・drainする
  on_destroy = {
    reset    = true
    graceful = true
    reboot   = false
  }

  lifecycle {
    create_before_destroy = true
    # NOTE: インスタンスの置換に合わせて古いノード宛てのresetを走らせるには置換が必要。
    #       稼働中のノードをresetするため、置換でだけ変わるidを参照
    replace_triggered_by = [vultr_instance.this.id]
  }
}

# NOTE: 古いノードのdrainとインスタンスの削除を、新しいノードがReadyになった後に行わせるための待ち合わせ。
# create_before_destroyにより、古いtalos_machine_configuration_applyとvultr_instanceの削除はこのリソースの作成の後になる
resource "terraform_data" "node_ready" {
  triggers_replace = vultr_instance.this.id
  input            = vultr_instance.this.hostname

  depends_on = [talos_machine_configuration_apply.this]

  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.local_command.wait_node_ready]
      # NOTE: 失敗時に作り直させ、次のapplyでも古いノードを消す前にReadyを待たせる
      on_failure = taint
    }
  }
}

# NOTE: ISOを付けたままのインスタンスは再起動時にISOから起動するため、インストール後のReadyを待ってから外す。
# 古いノードのdrainをISOを外した後の再起動より後にするため、talos_machine_configuration_applyにも依存させる
resource "terraform_data" "iso_detached" {
  triggers_replace = vultr_instance.this.id
  input            = vultr_instance.this.hostname

  depends_on = [talos_machine_configuration_apply.this, terraform_data.node_ready]

  lifecycle {
    action_trigger {
      events     = [after_create]
      actions    = [action.local_command.detach_iso]
      on_failure = taint
    }
  }
}

# NOTE: destroy時のactionのconfigはplan時に既知である必要があるため、作成後に変わらないtalosconfigを渡し、kubeconfigはスクリプトがその場で取得する。
# talosconfigは引数・環境変数に置かず、エラー時の診断やプロセス一覧に出ないstdinで渡す
action "local_command" "wait_node_ready" {
  config {
    command   = "go"
    arguments = ["run", "-C", "${path.module}/scripts", "./cmd/kube-node", "wait-ready"]
    stdin = jsonencode({
      node_name      = caller.input
      talosconfig    = var.talosconfig
      talos_endpoint = var.talos_endpoint
    })
  }
}

action "local_command" "delete_node" {
  config {
    command   = "go"
    arguments = ["run", "-C", "${path.module}/scripts", "./cmd/kube-node", "delete"]
    stdin = jsonencode({
      node_name      = caller.hostname
      talosconfig    = var.talosconfig
      talos_endpoint = var.talos_endpoint
    })
  }
}

# NOTE: Vultr APIのキーは、Terraformの実行環境の環境変数VULTR_API_KEYをスクリプトが読む
action "local_command" "detach_iso" {
  config {
    command   = "go"
    arguments = ["run", "-C", "${path.module}/scripts", "./cmd/kube-node", "detach-iso"]
    stdin = jsonencode({
      node_name      = caller.input
      instance_id    = caller.triggers_replace
      talosconfig    = var.talosconfig
      talos_endpoint = var.talos_endpoint
    })
  }
}
