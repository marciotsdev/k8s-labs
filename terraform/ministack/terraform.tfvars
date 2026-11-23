gateway             = "192.168.15.1"
ssh_public_key_path = "~/.ssh/homelab_ed25519.pub"

# Recriando o MiniStack (emulador local de API AWS -- Lambda/SQS/DynamoDB/S3)
# pra validar Crossplane provisionando infra de tamanhos diferentes por
# estagio (dev/qa/stage/prod), decisao de 2026-11-23. A VM original (mesmo
# vm_id/IP) foi destruida de proposito em 2026-10-28, junto com o resto do
# homelab-iac -- so o codigo sobreviveu no GitHub
# (marciotsdev/homelab-iac, ansible/roles/ministack), portado pra ca.
vms = {
  ministack = {
    vm_id         = 2007
    ip            = "192.168.15.56/24"
    cores         = 4
    memory        = 4096
    disk          = 40
    # Migrado pro data02-thin em 2026-11-23 -- junta com os utilitarios
    # leves (nfs-ganesha, floci-az) nesse pool, fora do pve.
    datastore_id  = "data02-thin"
    tags          = ["lab", "env-multi-stage"]
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
