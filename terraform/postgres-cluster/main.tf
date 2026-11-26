module "vms" {
  source = "../modules/vm-fleet"

  proxmox_node        = var.proxmox_node
  template_vm_id      = var.template_vm_id
  network_bridge      = var.network_bridge
  gateway             = var.gateway
  datastore_id        = var.datastore_id
  ssh_public_key_path = var.ssh_public_key_path
  vm_user             = var.vm_user
  vms                 = var.vms
}
