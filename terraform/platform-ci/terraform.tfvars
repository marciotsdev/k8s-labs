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
    vm_id  = 2021
    ip     = "192.168.15.70/24"
    cores  = 4
    memory = 8192
    # 40 -> 80: Buildah com STORAGE_DRIVER=vfs nao usa copy-on-write (cada
    # "buildah from" duplica a camada inteira), e o Tekton nao limpa Pods/
    # Workspaces sozinho -- varias tentativas de pipeline no mesmo dia
    # encheram o disco de verdade (achado em 2026-11-12, kubelet evictando
    # pod por ephemeral-storage).
    disk          = 80
    # Migrado pro data02-thin em 2026-11-23 -- era um dos dois que mais
    # pesavam no pool pve (~61GB reais de 80GB nominal), ver [[k8s-labs]]
    # memoria, incidente do pool cheio. Mecanismo (move de disco ao vivo,
    # update in-place, sem downtime) ja validado antes no nfs-ganesha.
    datastore_id  = "data02-thin"
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
    vm_id = 2023
    ip    = "192.168.15.72/24"
    # 2 cores/6144MB -> 4 cores/8192MB: node chegou a 97.78% CPU e 100.69%
    # memoria (estourando pra swap) rodando yarn install + bundle webpack
    # do build:backend/build:all (achado em 2026-11-14).
    cores           = 4
    memory          = 12288
    memory_floating = 12288
    # 122880 era TB, nao GB -- esse campo e em GB (diferente de "memory",
    # que e em MB). O erro de unidade passou pelo terraform apply sem falhar
    # porque local-lvm e thin-provisioned, e o growpart/resize2fs do
    # cloud-init corrompeu o ext4 tentando expandir a particao pra 120TB
    # de uma vez (achado em 2026-11-15, "Inode bitmap checksum does not
    # match bitmap"). VM recriada do zero com o valor certo.
    disk          = 120
    # Migrado pro data02-thin em 2026-11-23 -- completa o cluster k8s-ci
    # inteiro no mesmo pool (cp/w2 ja migrados antes).
    datastore_id  = "data02-thin"
    tags          = ["lab", "k8s", "env-platform-ci"]
    agent_enabled = true
    dns_servers   = ["192.168.15.65", "192.168.15.1"]
    ssh_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBO3BiGOxRN29Jfas+UGS0hV+JGKZedAl+IMpzwrzLs8 homelab-terraform-ansible",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBogEzcV72H1vVmvC849JTMTFYguxVw5QKl4JX85fRj0 thundercat@windows-claude",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJJbotLXtaqwLd2a8vYRCOO3YbpMgIuMevYKhz9NoHJ4 root@pve",
    ]
  }
  k8s-ci-w2 = {
    # Segundo agent do cluster k8s-ci -- distribui a carga do Tekton entre
    # dois workers em vez de concentrar tudo no w1 (achado em 2026-11-15:
    # um unico worker vira gargalo de disco/memoria quando o pipeline falha
    # e reroda varias vezes seguidas).
    vm_id         = 2024
    ip            = "192.168.15.73/24"
    cores         = 4
    memory        = 12288
    disk          = 120
    # Migrado pro data02-thin em 2026-11-23 -- o outro que mais pesava no
    # pool pve (~59GB reais de 120GB nominal), junto com o k8s-ci-cp acima.
    datastore_id  = "data02-thin"
    tags          = ["lab", "k8s", "env-platform-ci"]
    agent_enabled = true
    dns_servers   = ["192.168.15.65", "192.168.15.1"]
    ssh_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBO3BiGOxRN29Jfas+UGS0hV+JGKZedAl+IMpzwrzLs8 homelab-terraform-ansible",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBogEzcV72H1vVmvC849JTMTFYguxVw5QKl4JX85fRj0 thundercat@windows-claude",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJJbotLXtaqwLd2a8vYRCOO3YbpMgIuMevYKhz9NoHJ4 root@pve",
    ]
  }
  nfs-ganesha = {
    # VM dedicada so pra storage compartilhado (NFS-Ganesha), consumido via
    # csi-driver-nfs pelos workers do k8s-ci -- resolve a causa raiz do
    # workspace "shared-data" ser preso a um unico node (local-path-
    # provisioner e RWO node-afim). Decisao (2026-11-19): VM propria em vez
    # de pod dentro do cluster, pra nao criar dependencia circular (se o
    # node que hospedasse o pod do Ganesha tivesse problema, toda PVC NFS
    # travaria junto -- ironicamente o mesmo problema que estamos resolvendo).
    # vm_id 2028/.77: proximos livres apos platform-backstage-w2 (2027/.76).
    vm_id         = 2028
    ip            = "192.168.15.77/24"
    cores         = 2
    memory        = 2048
    disk          = 40
    # TESTE em 2026-11-23: datastore_id trocado de local-lvm (default) pra
    # data02-thin, só pra ver via `terraform plan` se o provider trata isso
    # como update in-place (move de disco ao vivo) ou force replacement
    # (destroi e recria a VM) -- NAO aplicar sem confirmar qual dos dois.
    datastore_id  = "data02-thin"
    tags          = ["lab", "env-platform-ci"]
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
