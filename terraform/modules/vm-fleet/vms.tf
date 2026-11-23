resource "proxmox_virtual_environment_vm" "this" {
  for_each = var.vms

  name          = each.key
  node_name     = var.proxmox_node
  vm_id         = each.value.vm_id
  tags          = each.value.tags
  on_boot       = each.value.on_boot
  description   = each.value.description
  scsi_hardware = each.value.scsi_hardware

  clone {
    vm_id = coalesce(each.value.template_vm_id, var.template_vm_id)
    full  = true
  }

  agent {
    enabled = each.value.agent_enabled
  }

  cpu {
    cores   = each.value.cores
    sockets = each.value.sockets
    type    = each.value.cpu_type
  }

  memory {
    dedicated = each.value.memory
    # floating < dedicated habilita o balloon device (floating = minimo
    # garantido ao guest, dedicated = teto). Sem isso o host nao reclama RAM
    # ociosa do guest -- ver comentario em variables.tf.
    floating = coalesce(each.value.memory_floating, floor(each.value.memory / 2))
  }

  disk {
    datastore_id = coalesce(each.value.datastore_id, var.datastore_id)
    interface    = each.value.disk_interface
    size         = each.value.disk
    # "ignore" (default do provider) nunca repassa TRIM do guest pro pool
    # thin do Proxmox -- dado apagado dentro da VM fica preso como bloco
    # "alocado" pra sempre, mesmo sem uso real. Isso encheu o local-lvm de
    # verdade (100% de dados reais) e derrubou 3 VMs com io-error em
    # 2026-11-23 (achado no k8s-ci-w1, que acumulava builds do Buildah).
    # "on" repassa o TRIM -- ainda assim precisa rodar `fstrim` (ou ter
    # fstrim.timer ativo) dentro do guest pra devolver o espaço de verdade.
    discard = "on"
  }

  network_device {
    bridge   = var.network_bridge
    firewall = each.value.nic_firewall
  }

  dynamic "initialization" {
    for_each = each.value.cloudinit ? [1] : []
    content {
      datastore_id = coalesce(each.value.datastore_id, var.datastore_id)

      ip_config {
        ipv4 {
          address = each.value.ip
          gateway = var.gateway
        }
      }

      dynamic "dns" {
        for_each = each.value.dns_servers != null ? [1] : []
        content {
          servers = each.value.dns_servers
        }
      }

      user_account {
        username = var.vm_user
        keys     = coalesce(each.value.ssh_keys, [trimspace(file(pathexpand(var.ssh_public_key_path)))])
      }
    }
  }

  operating_system {
    type = "l26"
  }

  serial_device {
    device = "socket"
  }

  lifecycle {
    ignore_changes = [started, clone]
  }
}
