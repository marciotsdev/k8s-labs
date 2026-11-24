gateway             = "192.168.15.1"
ssh_public_key_path = "~/.ssh/homelab_ed25519.pub"

# vm_id 2031, IP .80: proximos livres acima do floci-az (2030/.79). VM
# dedicada pro Wazuh (SIEM) -- decisao de 2026-11-24 de consolidar em vez de
# instalar ferramenta por camada (substitui Lynis via SCA e o Loki/Fluent
# Bit planejado via Indexer, Falco vira log source dela quando implementado).
#
# Dimensionamento oficial do Wazuh pesquisado em 2026-11-24 (quickstart da
# documentacao) tem 3 faixas por numero de agentes: 1-25 (4 vCPU/8GB/50GB),
# 26-50 (8 vCPU/8GB/100GB) e 51-100 (8 vCPU/8GB/200GB). O lab tem 10 hosts
# hoje (3 k8s-ci + 4 k8s-backstage + semaphore-ui + nfs-ganesha + ministack
# + floci-az) -- caberia na faixa menor, mas decisao explicita (24/11) de
# usar a faixa 26-50 de proposito, com folga pro ambiente crescer sem
# precisar redimensionar a VM depois.
vms = {
  wazuh = {
    vm_id         = 2031
    ip            = "192.168.15.80/24"
    cores         = 8
    memory        = 8192
    disk          = 100
    # data02-thin -- mesmo pool dos utilitarios leves recentes (ministack,
    # floci-az, nfs-ganesha), fora do pve.
    datastore_id  = "data02-thin"
    tags          = ["lab", "security"]
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
