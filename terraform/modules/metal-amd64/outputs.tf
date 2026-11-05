output "iso_url" {
  value       = local.iso_url
  description = "ノードを起動するTalosのISOのURL"
}

output "talos_machine_id" {
  value       = talos_machine.this.id
  description = "talos_machineのID。他のノードのupgrade_afterに渡し、Talosの更新の順序を付ける"
}
