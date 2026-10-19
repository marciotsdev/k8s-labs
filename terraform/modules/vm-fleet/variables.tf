variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "template_vm_id" {
  type    = number
  default = 9000
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "gateway" {
  type        = string
  description = "Network gateway for the cloned VMs, e.g. 192.168.1.1"
}

variable "datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to the SSH public key injected into cloned VMs via cloud-init, e.g. ~/.ssh/id_ed25519.pub"
}

variable "vm_user" {
  type    = string
  default = "ubuntu"
}

variable "vms" {
  description = "Map of VMs to create by cloning a base template. Optional fields default to the fleet standard."
  type = map(object({
    vm_id  = number
    ip     = string
    cores  = number
    memory = number
    disk   = number

    sockets        = optional(number, 1)
    cpu_type       = optional(string, "host")
    tags           = optional(list(string), ["lab"])
    on_boot        = optional(bool, false)
    template_vm_id = optional(number)
    datastore_id   = optional(string)
    disk_interface = optional(string, "scsi0")
    nic_firewall   = optional(bool, false)
    cloudinit      = optional(bool, true)
    ssh_keys       = optional(list(string))
    dns_servers    = optional(list(string))
    agent_enabled  = optional(bool, false)
    description    = optional(string)
    scsi_hardware  = optional(string, "virtio-scsi-pci")
  }))
}
