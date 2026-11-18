output "iso_url" {
  value       = local.iso_url
  description = "ノードの起動に使うTalos ISOのURL"
}

output "talos_machine_id" {
  value       = talos_machine.this.id
  description = "talos_machineのID。ほかのノードのupgrade_afterに渡し、Talosを更新する順序を付ける"
}
