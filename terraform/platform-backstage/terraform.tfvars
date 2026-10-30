gateway             = "192.168.15.1"
ssh_public_key_path = "~/.ssh/homelab_ed25519.pub"

# vm_id 2022, IP .71: proximos livres acima do platform-ci (2021/.70).
# Cluster single-node, separado de proposito (ver platform-ci/terraform.tfvars
# para o raciocinio de blast radius).
vms = {
  k8s-backstage-cp = {
    # Backstage (depois tambem Keycloak) -- recebe deploy cross-cluster
    # disparado pelo Tekton no platform-ci.
    vm_id         = 2022
    ip            = "192.168.15.71/24"
    cores         = 2
    memory        = 4096
    disk          = 30
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
