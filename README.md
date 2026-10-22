# k8s-labs

IaC separada (não faz parte de `homelab-iac` nem `homelab-gitops`) para um
cluster k3s multi-nó dedicado a praticar troubleshooting avançado e validar
KEDA, Karpenter e Kustomize, sem misturar esse experimento com a plataforma
"de produção" do lab.

## Topologia

| VM | vm_id | IP | Papel |
|---|---|---|---|
| k8s-labs-cp | 2018 | 192.168.15.67 | k3s server (control plane) |
| k8s-labs-w1 | 2019 | 192.168.15.68 | k3s agent |
| k8s-labs-w2 | 2020 | 192.168.15.69 | k3s agent |

IPs `.67`-`.69`: primeiros livres acima da frota atual (`.50`-`.66`), dentro
da faixa estática `.1`-`.99` (a faixa dinâmica do DHCP foi reduzida para
`.100`-`.250`). VM IDs `2018`-`2020`: primeiros livres acima do maior ID
existente (`2017`, uyuni).

## Provisionar

```bash
cd terraform/cluster
terraform init
terraform plan
terraform apply
```

```bash
cd ../../ansible
ansible-playbook -i inventory/hosts.ini site.yml
```

O `site.yml` sobe o k3s (server + 2 agents via token compartilhado em
`secrets/k3s_cluster_token`, já gerado), depois instala KEDA e Karpenter no
server.

## O que tem aqui

- **KEDA**: cluster-agnostic, sem nenhuma dependência de nuvem. Exemplos em
  `manifests/keda/` (scaler por cron e por CPU).
- **Karpenter**: **provisionamento real validado, ponta a ponta**, via o
  provider
  [sergelogvinov/karpenter-provider-proxmox](https://github.com/sergelogvinov/karpenter-provider-proxmox)
  (fala direto com a API do Proxmox, não AWS/MiniStack). Documentado em
  [docs/karpenter-proxmox.md](docs/karpenter-proxmox.md) — o Karpenter cria
  uma VM real no Proxmox, escolhe o tamanho sozinho, o cloud-init customizado
  instala e junta o k3s como agent, e **o node aparece `Ready` no
  `kubectl get nodes`** e roda workload de verdade. Desprovisionamento também
  valida (VM removida do Proxmox sozinha; só o objeto `Node` do Kubernetes
  precisa de limpeza manual, ver doc). A primeira tentativa (apontar o
  provider **AWS** do Karpenter pro MiniStack) ficou documentada à parte em
  [docs/karpenter-ministack.md](docs/karpenter-ministack.md) como achado real
  — o controller nem chega a subir (`panic` em
  `DescribeInstanceTypeOfferings`) — mas foi abandonada em favor do provider
  Proxmox.
- **Kustomize**: playground de troubleshooting em
  `manifests/kustomize-playground/` — uma base saudável e overlays que
  quebram de propósito (probe na porta errada, memory limit baixo demais),
  cada um em seu próprio namespace, para praticar diagnóstico.

## Convenções herdadas do resto do lab

- Módulo Terraform `vm-fleet` (clone do template `9000`, cloud-init real) —
  mesmo módulo usado em `homelab-gitops`.
- Segredos em `secrets/`, nunca commitados (ver `.gitignore`).
- Chave SSH `~/.ssh/homelab_ed25519` para o usuário `ubuntu` em todas as VMs.
