gateway             = "192.168.15.1"
ssh_public_key_path = "~/.ssh/homelab_ed25519.pub"

# vm_id 2025, IP .74: proximo livre acima de toda a frota existente
# (k8s-labs 2018-2020/.67-.69, platform-ci 2021/2023/2024/.70/.72/.73,
# platform-backstage 2022/.71).
vms = {
  semaphore-ui = {
    # VM dedicada pra orquestracao de infra (Ansible/Terraform via UI) --
    # deliberadamente fora de qualquer cluster k3s, pra nao competir por
    # recursos nem compartilhar blast radius com o que ela ajuda a gerenciar.
    vm_id         = 2025
    ip            = "192.168.15.74/24"
    cores         = 2
    memory        = 4096
    disk          = 40
    # Migrado pro data02-thin em 2026-11-23 -- junta com os utilitarios
    # leves nesse pool, fora do pve.
    datastore_id  = "data02-thin"
    tags          = ["lab", "ops"]
    agent_enabled = true
    dns_servers   = ["192.168.15.65", "192.168.15.1"]
    ssh_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBO3BiGOxRN29Jfas+UGS0hV+JGKZedAl+IMpzwrzLs8 homelab-terraform-ansible",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBogEzcV72H1vVmvC849JTMTFYguxVw5QKl4JX85fRj0 thundercat@windows-claude",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJJbotLXtaqwLd2a8vYRCOO3YbpMgIuMevYKhz9NoHJ4 root@pve",
    ]
  }
}

template_vm_id = 9000
