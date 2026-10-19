output "vm_ips" {
  value = { for k, v in var.vms : k => split("/", v.ip)[0] }
}

output "vm_ids" {
  value = { for k, v in proxmox_virtual_environment_vm.this : k => v.vm_id }
}
