gateway             = "192.168.15.1"
ssh_public_key_path = "~/.ssh/homelab_ed25519.pub"

# vm_id 2032/2033/2034, IP .81/.82/.83: proximos livres acima do wazuh
# (2031/.80). Cluster de Postgres compartilhado pro lab inteiro (Forgejo
# primeiro, Backstage depois) -- decisao de 2026-11-26, nasceu da
# constatacao de que o Forgejo e "single-node, sem HA" (SQLite, replicaCount
# fixo em 1 no chart). Os 3 nos sao pares -- cada um roda Postgres + Patroni
# + um membro do etcd (DCS), sem VM dedicada so pro etcd (padrao de
# referencia do proprio Patroni). HAProxy expoe um endereco fixo unico na
# frente, roteando sempre pro no que o Patroni elegeu como lider.
#
# Datastore local (data02-thin) de proposito, igual todo o resto das VMs
# utilitarias (ministack/floci-az/wazuh) -- este lab tem um unico host
# Proxmox fisico, entao nenhuma escolha de datastore muda a resiliencia a
# falha de hardware (as 3 VMs caem juntas se o host cair, independente de
# qual pool usarem). O HA do Patroni protege contra falha de processo/VM
# individual, nao de host fisico -- e exige discos INDEPENDENTES por no
# (replicacao shared-nothing, 3 copias completas do dado), nunca um
# datastore compartilhado entre elas (isso seria o modelo antigo de
# storage compartilhado + failover, incompativel com o Patroni).
#
# RAM revisada em 2026-11-26 (2GB -> 3GB), referencia:
# https://massivegrid.com/blog/postgresql-server-requirements-shared-buffers-replication-hosting-cost/
# -- shared_buffers recomendado e 25% da RAM; carga aqui e metadado puro
# (Forgejo, depois Backstage), bem abaixo do menor working set que a
# referencia cita (~500MB -> ~2GiB de no). 3GB da folga de proposito pro
# etcd+Patroni rodarem no mesmo no sem disputar memoria com o Postgres --
# mesmo principio ja aplicado no Wazuh depois do heap do Indexer ter sido
# reduzido sozinho por falta de RAM.
vms = {
  postgres-shared-1 = {
    vm_id         = 2032
    ip            = "192.168.15.81/24"
    cores         = 2
    memory        = 3072
    disk          = 30
    datastore_id  = "data02-thin"
    tags          = ["lab", "data"]
    agent_enabled = true
    dns_servers   = ["192.168.15.65", "192.168.15.1"]
    ssh_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBO3BiGOxRN29Jfas+UGS0hV+JGKZedAl+IMpzwrzLs8 homelab-terraform-ansible",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBogEzcV72H1vVmvC849JTMTFYguxVw5QKl4JX85fRj0 thundercat@windows-claude",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJJbotLXtaqwLd2a8vYRCOO3YbpMgIuMevYKhz9NoHJ4 root@pve",
    ]
  }
  postgres-shared-2 = {
    vm_id         = 2033
    ip            = "192.168.15.82/24"
    cores         = 2
    memory        = 3072
    disk          = 30
    datastore_id  = "data02-thin"
    tags          = ["lab", "data"]
    agent_enabled = true
    dns_servers   = ["192.168.15.65", "192.168.15.1"]
    ssh_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBO3BiGOxRN29Jfas+UGS0hV+JGKZedAl+IMpzwrzLs8 homelab-terraform-ansible",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBogEzcV72H1vVmvC849JTMTFYguxVw5QKl4JX85fRj0 thundercat@windows-claude",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJJbotLXtaqwLd2a8vYRCOO3YbpMgIuMevYKhz9NoHJ4 root@pve",
    ]
  }
  postgres-shared-3 = {
    vm_id         = 2034
    ip            = "192.168.15.83/24"
    cores         = 2
    memory        = 3072
    disk          = 30
    datastore_id  = "data02-thin"
    tags          = ["lab", "data"]
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
