gateway             = "192.168.15.1"
ssh_public_key_path = "~/.ssh/homelab_ed25519.pub"

# vm_id 2022, IP .71: proximos livres acima do platform-ci (2021/.70).
# Cluster deixou de ser single-node em 2026-11-17 -- 2 agents adicionados
# (vm_id 2026/2027, IP .75/.76, proximos livres acima do semaphore-ui
# 2025/.74) pra rodar o Backstage com replicas/Rollouts de verdade, em vez
# de criar um cluster novo do zero (decisao: reaproveitar o cluster que ja
# e conceitualmente "o de apps" no fluxo de entrega).
#
# Resize + 3o worker em 2026-11-23: vai hospedar multi-stage (dev/qa/stage/
# prod) como namespaces neste mesmo cluster -- precisa de mais capacidade
# por node (cada namespace roda seu proprio Backstage+Postgres) e de um
# worker a mais pra distribuir isso. O comentario antigo dizia "cores
# enxutos porque CPU e escasso" -- isso ficou desatualizado: o
# desprovisionamento das 17 VMs do homelab-iac/gitops (28/10) liberou a
# maior parte da capacidade do host (confirmado no dashboard do Proxmox:
# 24 vCPU totais, so 12% em uso). Cores dobrados pra 4 em todos os nodes,
# RAM pra 8192, disco pra 50 (varios Postgres/imagens por namespace).
vms = {
  k8s-backstage-cp = {
    # Backstage (depois tambem Keycloak) -- recebe deploy cross-cluster
    # disparado pelo Tekton no platform-ci.
    vm_id         = 2022
    ip            = "192.168.15.71/24"
    cores         = 4
    memory        = 8192
    disk          = 50
    # Migrado pro DATA (thick/lvm, disco de 4TB, 2026-11-23) -- cluster
    # k8s-backstage inteiro vai pra esse pool (maior cluster, maior pool,
    # thick = sem risco de overcommit, mais seguro pra producao-de-lab).
    datastore_id  = "DATA"
    tags          = ["lab", "k8s", "env-platform-backstage"]
    agent_enabled = true
    dns_servers   = ["192.168.15.65", "192.168.15.1"]
    ssh_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBO3BiGOxRN29Jfas+UGS0hV+JGKZedAl+IMpzwrzLs8 homelab-terraform-ansible",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBogEzcV72H1vVmvC849JTMTFYguxVw5QKl4JX85fRj0 thundercat@windows-claude",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJJbotLXtaqwLd2a8vYRCOO3YbpMgIuMevYKhz9NoHJ4 root@pve",
    ]
  }
  k8s-backstage-w1 = {
    vm_id         = 2026
    ip            = "192.168.15.75/24"
    cores         = 4
    memory        = 8192
    disk          = 50
    datastore_id  = "DATA" # mesmo motivo do k8s-backstage-cp acima
    tags          = ["lab", "k8s", "env-platform-backstage"]
    agent_enabled = true
    dns_servers   = ["192.168.15.65", "192.168.15.1"]
    ssh_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBO3BiGOxRN29Jfas+UGS0hV+JGKZedAl+IMpzwrzLs8 homelab-terraform-ansible",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBogEzcV72H1vVmvC849JTMTFYguxVw5QKl4JX85fRj0 thundercat@windows-claude",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJJbotLXtaqwLd2a8vYRCOO3YbpMgIuMevYKhz9NoHJ4 root@pve",
    ]
  }
  k8s-backstage-w2 = {
    vm_id         = 2027
    ip            = "192.168.15.76/24"
    cores         = 4
    memory        = 8192
    disk          = 50
    datastore_id  = "DATA" # mesmo motivo do k8s-backstage-cp acima
    tags          = ["lab", "k8s", "env-platform-backstage"]
    agent_enabled = true
    dns_servers   = ["192.168.15.65", "192.168.15.1"]
    ssh_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBO3BiGOxRN29Jfas+UGS0hV+JGKZedAl+IMpzwrzLs8 homelab-terraform-ansible",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBogEzcV72H1vVmvC849JTMTFYguxVw5QKl4JX85fRj0 thundercat@windows-claude",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJJbotLXtaqwLd2a8vYRCOO3YbpMgIuMevYKhz9NoHJ4 root@pve",
    ]
  }
  k8s-backstage-w3 = {
    # 3o worker, adicionado pra multi-stage (ver comentario acima) -- vm_id
    # 2029/IP .78: proximos livres acima do ministack (2007 reutilizado) e
    # do nfs-ganesha (2028/.77).
    vm_id         = 2029
    ip            = "192.168.15.78/24"
    cores         = 4
    memory        = 8192
    disk          = 50
    datastore_id  = "DATA" # mesmo motivo do k8s-backstage-cp acima
    tags          = ["lab", "k8s", "env-platform-backstage"]
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
