# VM separada pra ferramentas de "plataforma de operacao" do lab que nao
# sao parte de nenhum cluster k3s (ex: Semaphore UI, patch management).
# Deliberadamente fora do platform-ci/platform-backstage/k8s-labs --
# ferramenta de orquestracao de infra nao deveria competir por recursos
# nem compartilhar blast radius com os clusters que ela ajuda a gerenciar.
module "vms" {
  source = "../modules/vm-fleet"

  proxmox_node        = var.proxmox_node
  template_vm_id      = var.template_vm_id
  network_bridge      = var.network_bridge
  gateway             = var.gateway
  datastore_id        = var.datastore_id
  ssh_public_key_path = var.ssh_public_key_path
  vm_user             = var.vm_user
  vms                 = var.vms
}
