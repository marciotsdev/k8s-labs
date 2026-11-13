gateway             = "192.168.15.1"
ssh_public_key_path = "~/.ssh/homelab_ed25519.pub"

# vm_id 2021/2023, IP .70/.72: proximos livres acima do trio k8s-labs
# (2018-2020 / .67-.69) e do platform-backstage (2022/.71), ainda dentro da
# faixa estatica .1-.99. Separado do k8s-labs principal de proposito (blast
# radius: se o Forgejo ou o Tekton quebrar, o Backstage em platform-backstage
# continua de pe). Ganhou o primeiro agent (k8s-ci-w1) em 2026-11-12 -- nao
# e mais single-node, disco do cp cheio de verdade com Buildah+vfs.
vms = {
  k8s-ci-cp = {
    # Forgejo (repo git + registry) + Tekton (CI/CD nativo de k8s), cluster
    # de plataforma separado do k8s-labs principal e do platform-backstage.
    vm_id         = 2021
    ip            = "192.168.15.70/24"
    cores         = 4
    memory        = 8192
    # 40 -> 80: Buildah com STORAGE_DRIVER=vfs nao usa copy-on-write (cada
    # "buildah from" duplica a camada inteira), e o Tekton nao limpa Pods/
    # Workspaces sozinho -- varias tentativas de pipeline no mesmo dia
    # encheram o disco de verdade (achado em 2026-11-12, kubelet evictando
    # pod por ephemeral-storage).
    disk          = 80
    tags          = ["lab", "k8s", "env-platform-ci"]
    agent_enabled = true
    dns_servers   = ["192.168.15.65", "192.168.15.1"]
    ssh_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBO3BiGOxRN29Jfas+UGS0hV+JGKZedAl+IMpzwrzLs8 homelab-terraform-ansible",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBogEzcV72H1vVmvC849JTMTFYguxVw5QKl4JX85fRj0 thundercat@windows-claude",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJJbotLXtaqwLd2a8vYRCOO3YbpMgIuMevYKhz9NoHJ4 root@pve",
    ]
  }
  k8s-ci-w1 = {
    # Primeiro agent do cluster k8s-ci -- ate agora single-node de proposito
    # (ver comentario no topo deste arquivo). Adicionado pra dar mais
    # ephemeral-storage/CPU disponivel pros Pods do pipeline Tekton, que
    # hoje disputam tudo com o control plane no mesmo node.
    vm_id         = 2023
    ip            = "192.168.15.72/24"
    cores         = 2
    memory        = 6144
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
