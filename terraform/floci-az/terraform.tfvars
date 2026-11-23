gateway             = "192.168.15.1"
ssh_public_key_path = "~/.ssh/homelab_ed25519.pub"

# VM dedicada pro floci-az (emulador local de Azure -- Blob/Queue/Table,
# Cosmos DB, SQL/Postgres/MySQL, Functions, AKS, Service Bus, Event Hubs...),
# decisao de 2026-11-23: VM propria em vez de reaproveitar a do MiniStack,
# pelo mesmo motivo do nfs-ganesha -- nao acoplar o blast radius de dois
# emuladores de nuvem diferentes (se um travar/lotar disco, o outro
# continua de pe). vm_id 2030/IP .79: proximos livres acima do
# k8s-backstage-w3 (2029/.78).
#
# datastore_id = "data02-thin" (nao o default "local-lvm") de proposito --
# usa o pool thin novo criado na VG DATA02 (ate entao 100% ociosa), em vez
# de adicionar mais pressao no pool "pve" que ja ficou cheio de verdade
# nesta mesma sessao (ver [[k8s-labs]] memoria, incidente de 2026-11-23).
vms = {
  floci-az = {
    vm_id         = 2030
    ip            = "192.168.15.79/24"
    cores         = 4
    memory        = 4096
    disk          = 40
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
