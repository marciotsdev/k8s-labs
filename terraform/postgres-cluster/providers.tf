terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
    }
  }
}

# Credenciais via PROXMOX_VE_ENDPOINT / PROXMOX_VE_API_TOKEN / PROXMOX_VE_INSECURE
# (mesmo padrao do restante do k8s-labs) -- nunca armazenadas neste repo.
provider "proxmox" {}
