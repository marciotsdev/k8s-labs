# Karpenter contra o Proxmox — provisionamento real validado

Depois do [achado documentado contra o MiniStack](karpenter-ministack.md) (o controller do provider AWS
nem chega a inicializar), a abordagem mudou de vez: em vez de simular AWS, usar
**[sergelogvinov/karpenter-provider-proxmox](https://github.com/sergelogvinov/karpenter-provider-proxmox)**
— um provider comunitário (137+ estrelas, Apache-2.0, mantenedor conhecido na comunidade
Talos/Proxmox/Kubernetes) que fala direto com a API do Proxmox, criando VMs reais como nodes.

**Resultado: funciona de verdade.** O controller sobe limpo (sem panic), autentica, e provisiona VMs
reais no Proxmox do lab, escolhendo o tamanho sozinho a partir de uma lista de tipos de instância
pré-definida (famílias `c1`/`t1`/`s1`/`m1`/`x1`, 1 a 16 vCPU).

## Pré-requisitos no Proxmox

Role dedicado, sem privilégios de admin total:

```bash
pveum role add Karpenter -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Mapping.Audit Mapping.Use Sys.Audit Sys.AccessNetwork SDN.Audit SDN.Use VM.Audit VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Memory VM.Config.Disk VM.Config.Network VM.Config.HWType VM.Config.Cloudinit VM.Config.Options VM.PowerMgmt"
pveum user add kubernetes@pve
pveum aclmod / -user kubernetes@pve -role Karpenter
pveum user token add kubernetes@pve karpenter -privsep 1 --comment "Kubernetes Karpenter (k8s-labs)"
pveum aclmod / --token 'kubernetes@pve!karpenter' -role Karpenter
```

Token salvo em `secrets/karpenter_proxmox_token_id` e `secrets/karpenter_proxmox_token_secret`
(gitignored) → vira o secret `karpenter-provider-proxmox` no namespace `kube-system`:

```bash
cat > /tmp/karpenter-proxmox-config.yaml <<EOF
clusters:
  - url: https://192.168.15.7:8006/api2/json
    insecure: true
    token_id: "$(cat secrets/karpenter_proxmox_token_id)"
    token_secret: "$(cat secrets/karpenter_proxmox_token_secret)"
    region: pve
EOF
kubectl -n kube-system create secret generic karpenter-provider-proxmox --from-file=config.yaml=/tmp/karpenter-proxmox-config.yaml
rm /tmp/karpenter-proxmox-config.yaml
```

## Instalação

```bash
helm upgrade -i -n kube-system -f manifests/karpenter-proxmox/helm-values.yaml \
  karpenter-provider-proxmox oci://ghcr.io/sergelogvinov/charts/karpenter-provider-proxmox
```

`manifests/karpenter-proxmox/helm-values.yaml` usa `existingConfigSecret` (aponta pro secret já criado)
em vez de embutir a credencial dentro do próprio `values.yaml` do Helm — evita duplicar o segredo.

## CRDs aplicados, em ordem

1. **`unmanaged-template.yaml`** — `ProxmoxUnmanagedTemplate` apontando pro template `9000`
   (`ubuntu-2204-template`), já existente no lab (reaproveitado, não precisou de template novo).
2. **`nodeclass.yaml`** — `ProxmoxNodeClass`. **Pegadinha real**: o `bootDevice` default do CRD (30G)
   não tem `storage` explícito — sem isso o matching falha com `TemplatesNotFound`/`ZONES: 0`, porque o
   provider não sabe em qual storage criar o disco. Confirmar o storage real do template
   (`qm config 9000` → `local-lvm`) e declarar explicitamente:
   ```yaml
   bootDevice:
     size: 30Gi
     storage: local-lvm
   ```
3. **`nodepool.yaml`** — `NodePool` (mesmo CRD genérico `karpenter.sh/v1` usado pelo provider AWS),
   `limits` baixos de propósito pro primeiro teste.

## Disparar um provisionamento de teste

Um pod pedindo mais CPU do que qualquer node existente comporta força o scheduler a pedir ajuda ao
Karpenter:

```bash
kubectl apply -f manifests/karpenter-proxmox/trigger-pod.yaml
kubectl get nodeclaims -owide
```

**Pegadinha real**: a primeira tentativa pediu `1800m` de CPU — coube com folga num dos 3 nodes
existentes (2 vCPU cada), então o Karpenter nunca foi acionado. Só disparou com `2500m`, acima do teto
de qualquer node atual (2000m), não importa quanta folga sobrasse.

**Confirmado via `qm config <vmid>` no Proxmox** (não só `kubectl`): o Karpenter criou uma VM real com
`cores: 4, memory: 8192` (escolheu sozinho a instância `c1.4VCPU-8GB`, a primeira da lista que satisfazia
2500m), disco redimensionado de 2.2G (template) pra 33G, tags aplicadas, `status: running`.

Deletando o pod de teste, o `NodeClaim` desaparece sozinho após um intervalo de avaliação (minutos, não
instantâneo) e a VM é **completamente removida** do Proxmox — ciclo criar→usar→desprovisionar validado
ponta a ponta, sem nenhuma limpeza manual.

## Limitação atual, conhecida: o node não entra no cluster

Com `metadataOptions.type: none` (o que está em `nodeclass.yaml` hoje), **nenhum cloud-init é injetado**
na VM criada — ela sobe, mas nunca aparece em `kubectl get nodes`, porque não tem como saber o token de
join do k3s. O "bootstrap token" genérico que esse provider injeta via `metadataOptions.type: cdrom` é
pensado pro fluxo `kubeadm`, não pro jeito que o k3s se junta a um cluster (`K3S_URL`+`K3S_TOKEN`).

**Próximo passo** (não implementado ainda): trocar `metadataOptions.type` pra `cdrom`, com um Secret de
cloud-init customizado (`user-data` via go-template, ver
[docs do provider](https://github.com/sergelogvinov/karpenter-provider-proxmox/blob/main/docs/nodeclass.md))
que rode o instalador do k3s em modo agent contra `https://192.168.15.67:6443`, usando o mesmo token de
`secrets/k3s_cluster_token`.
