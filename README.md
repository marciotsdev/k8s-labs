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
- **Karpenter**: apontado para o MiniStack (emulador AWS já usado pelo
  Crossplane) via `AWS_ENDPOINT_URL`. Testado e documentado em
  [docs/karpenter-ministack.md](docs/karpenter-ministack.md) — o controller
  não chega a subir (`panic` em `DescribeInstanceTypeOfferings`, action que o
  MiniStack community não implementa). Fica instalado com 0 réplicas só
  pelos CRDs (`NodePool`/`EC2NodeClass`/`NodeClaim`), disponíveis pra estudo
  da API mesmo sem autoscaling funcional.
- **Kustomize**: playground de troubleshooting em
  `manifests/kustomize-playground/` — uma base saudável e overlays que
  quebram de propósito (probe na porta errada, memory limit baixo demais),
  cada um em seu próprio namespace, para praticar diagnóstico.

## Convenções herdadas do resto do lab

- Módulo Terraform `vm-fleet` (clone do template `9000`, cloud-init real) —
  mesmo módulo usado em `homelab-gitops`.
- Segredos em `secrets/`, nunca commitados (ver `.gitignore`).
- Chave SSH `~/.ssh/homelab_ed25519` para o usuário `ubuntu` em todas as VMs.
