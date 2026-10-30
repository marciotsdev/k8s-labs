gateway             = "192.168.15.1"
ssh_public_key_path = "~/.ssh/homelab_ed25519.pub"

# vm_id 2021, IP .70: proximos livres acima do trio k8s-labs (2018-2020 /
# .67-.69), ainda dentro da faixa estatica .1-.99. Cluster single-node,
# separado do k8s-labs principal de proposito (blast radius: se o Forgejo ou
# o Tekton quebrar, o Backstage em platform-backstage continua de pe).
vms = {
  k8s-ci-cp = {
    # Forgejo (repo git + registry) + Tekton (CI/CD nativo de k8s), cluster
    # de plataforma separado do k8s-labs principal e do platform-backstage.
    vm_id         = 2021
    ip            = "192.168.15.70/24"
    cores         = 4
    memory        = 8192
    disk          = 40
    tags          = ["lab", "k8s", "env-platform-ci"]
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
