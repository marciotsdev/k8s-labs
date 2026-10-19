gateway             = "192.168.15.1"
ssh_public_key_path = "~/.ssh/homelab_ed25519.pub"

# IPs .67-.69: primeiros livres acima da frota atual (.50-.66 ja em uso em
# homelab-iac/homelab-gitops), dentro da faixa estatica .1-.99 (dinamica do
# DHCP agora e .100-.250). vm_id 2018-2020: primeiros livres acima do maior
# ID existente (2017, uyuni).
vms = {
  k8s-labs-cp = {
    # Control plane (server) do cluster de estudo/troubleshooting - k3s
    # server + agents via token, cluster multi-no de proposito (ver docs/).
    vm_id       = 2018
    ip          = "192.168.15.67/24"
    cores       = 2
    memory      = 4096
    disk        = 30
    tags        = ["lab", "k8s", "env-labs"]
    dns_servers = ["192.168.15.65", "192.168.15.1"]
    ssh_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBO3BiGOxRN29Jfas+UGS0hV+JGKZedAl+IMpzwrzLs8 homelab-terraform-ansible",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBogEzcV72H1vVmvC849JTMTFYguxVw5QKl4JX85fRj0 thundercat@windows-claude",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJJbotLXtaqwLd2a8vYRCOO3YbpMgIuMevYKhz9NoHJ4 root@pve",
    ]
  }
  k8s-labs-w1 = {
    vm_id       = 2019
    ip          = "192.168.15.68/24"
    cores       = 2
    memory      = 4096
    disk        = 30
    tags        = ["lab", "k8s", "env-labs"]
    dns_servers = ["192.168.15.65", "192.168.15.1"]
    ssh_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBO3BiGOxRN29Jfas+UGS0hV+JGKZedAl+IMpzwrzLs8 homelab-terraform-ansible",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBogEzcV72H1vVmvC849JTMTFYguxVw5QKl4JX85fRj0 thundercat@windows-claude",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJJbotLXtaqwLd2a8vYRCOO3YbpMgIuMevYKhz9NoHJ4 root@pve",
    ]
  }
  k8s-labs-w2 = {
    vm_id       = 2020
    ip          = "192.168.15.69/24"
    cores       = 2
    memory      = 4096
    disk        = 30
    tags        = ["lab", "k8s", "env-labs"]
    dns_servers = ["192.168.15.65", "192.168.15.1"]
    ssh_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBO3BiGOxRN29Jfas+UGS0hV+JGKZedAl+IMpzwrzLs8 homelab-terraform-ansible",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBogEzcV72H1vVmvC849JTMTFYguxVw5QKl4JX85fRj0 thundercat@windows-claude",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJJbotLXtaqwLd2a8vYRCOO3YbpMgIuMevYKhz9NoHJ4 root@pve",
    ]
  }
}

template_vm_id = 9000
