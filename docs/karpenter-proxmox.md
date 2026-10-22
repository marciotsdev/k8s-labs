# Karpenter contra o Proxmox — provisionamento real validado

Depois do [achado documentado contra o MiniStack](karpenter-ministack.md) (o controller do provider AWS
nem chega a inicializar), a abordagem mudou de vez: em vez de simular AWS, usar
**[sergelogvinov/karpenter-provider-proxmox](https://github.com/sergelogvinov/karpenter-provider-proxmox)**
— um provider comunitário (137+ estrelas, Apache-2.0, mantenedor conhecido na comunidade
Talos/Proxmox/Kubernetes) que fala direto com a API do Proxmox, criando VMs reais como nodes.

**Resultado: funciona de verdade, ponta a ponta.** O controller sobe limpo (sem panic), autentica,
provisiona VMs reais no Proxmox do lab (escolhendo o tamanho sozinho a partir de uma lista de tipos de
instância pré-definida: famílias `c1`/`t1`/`s1`/`m1`/`x1`, 1 a 16 vCPU), e — com o cloud-init customizado
documentado abaixo — **o node entra de verdade no cluster k3s e roda workload**.

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

## Cloud-init customizado — o node entra de verdade no cluster

Com `metadataOptions.type: none` (primeira validação), a VM criada nunca aparecia em `kubectl get nodes`
— sem cloud-init, não tinha como saber o token de join do k3s. O "bootstrap token" genérico que esse
provider injeta via `metadataOptions.type: cdrom` é pensado pro fluxo `kubeadm`, não pro jeito que o k3s
se junta a um cluster (`K3S_URL`+`K3S_TOKEN`). **Resolvido**: `nodeclass.yaml` agora usa
`metadataOptions.type: cdrom`, com dois Secrets:

- **`k3s-cloudinit-templates`** (`kube-system`) — os templates em si (`user-data`, `network-config`),
  não-sensíveis, comitados em `manifests/karpenter-proxmox/cloudinit-user-data.yaml` e
  `cloudinit-network-config.yaml`.
- **`k3s-cloudinit-values`** (`kube-system`) — os valores reais (`K3sUrl`, `K3sToken`), nunca comitados,
  montado a partir de `secrets/k3s_cluster_token`.

```bash
kubectl -n kube-system create secret generic k3s-cloudinit-templates \
  --from-file=user-data=manifests/karpenter-proxmox/cloudinit-user-data.yaml \
  --from-file=network-config=manifests/karpenter-proxmox/cloudinit-network-config.yaml
kubectl -n kube-system create secret generic k3s-cloudinit-values \
  --from-literal=K3sUrl='https://192.168.15.67:6443' \
  --from-literal=K3sToken="$(cat secrets/k3s_cluster_token)"
```

### Pegadinhas reais encontradas (4, cada uma mascarando a próxima)

1. **O arquivo inteiro é processado como Go template, até dentro de comentários.** Escrever
   `{{ .Metadata.* }}` ou até `{{ }}` vazio como texto explicativo quebra o parser
   (`bad character '*'`, depois `missing value for command`) — tanto no `user-data` quanto, depois, no
   `network-config` (mesmo erro, arquivo diferente). Nunca usar a sintaxe de chaves-duplas em comentários
   explicativos, só nas ações de verdade.
2. **As aspas dentro de uma ação Go template não se escapam como num YAML externo.** Escrever
   `{{ get .Values \"K3sUrl\" }}` (pensando no escaping da string YAML externa) quebra o parser do Go
   template, que roda **antes** da leitura YAML e não entende `\"`. Fix: usar aspas simples na string
   YAML externa (`'...'`) e aspas normais dentro da ação (`{{ get .Values "K3sUrl" }}`) — sem colisão
   entre as duas camadas de sintaxe.
3. **`#cloud-config` precisa ser literalmente a primeira linha do arquivo.** Comentários explicativos
   antes dela fazem o cloud-init **ignorar o arquivo inteiro, em silêncio** (sem erro nenhum, o `runcmd`
   simplesmente nunca roda). Isso mascarou o bug por uma rodada inteira: a VM bootava e até mostrava o
   hostname certo no console — mas vindo de um mecanismo separado do Proxmox (SMBIOS
   `serial=h=<hostname>;i=<id>`), nada a ver com o nosso `user-data`.
4. **A interface de rede da VM se chama `ens18`, não `eth0`** (diferente das VMs criadas via Terraform
   neste mesmo lab, que ficam com `eth0` — motivo exato não investigado, parece ligado a como cada
   caminho de criação/clone lida com a numeração PCI). O `network-config` default do provider é fixo em
   `name: eth0` (valor estático de exemplo na doc, não gerado por VM) — sem a interface certa, a VM sobe
   com IPv6 automático (kernel, independe de cloud-init) mas **nenhum IPv4**, logo sem rota pro
   `K3S_URL`. Fix: `network-config` próprio fixando `name: ens18`.

### Diagnosticando sem rede nem SSH na VM

Enquanto a VM não tem IPv4, não tem como entrar nela. Duas técnicas usadas, nenhuma depende de
conectividade na VM:

1. **`qm guest cmd <vmid> network-get-interfaces`** no host Proxmox — funciona assim que o
   `qemu-guest-agent` sobe (prova que o `runcmd` já está executando), mesmo sem IPv4 configurado ainda.
   Foi assim que a pegadinha #4 (interface `ens18`) foi confirmada.
2. **Montar a própria ISO de cloud-init no host**, sem precisar de rede/SSH na VM nenhuma vez:
   ```bash
   find /var/lib/vz -iname '*custom-cloudinit*'
   mount -o loop,ro /var/lib/vz/template/iso/vm-<id>-custom-cloudinit.iso /mnt/ci-check
   cat /mnt/ci-check/user-data   # ja renderizado, com Metadata/Values substituidos de verdade
   umount /mnt/ci-check
   ```
   Foi assim que a pegadinha #3 (`#cloud-config` fora da primeira linha) foi confirmada — o `user-data`
   renderizado parecia perfeito, mas o cloud-init nunca tinha lido aquele arquivo.

### Achado lateral: sempre incluir acesso SSH desde a primeira versão

A primeira versão do `user-data` não tinha `users:`/`ssh_authorized_keys:` — se o `runcmd` falhasse (como
de fato falhou, pegadinha #3), não havia **nenhum** jeito de entrar na VM pra diagnosticar (sem senha de
console, sem guest agent, sem SSH). Corrigido adicionando as mesmas 3 chaves SSH públicas usadas no resto
do lab. Qualquer cloud-init customizado novo deveria incluir isso desde o início, não como correção
reativa.

## Resultado final: ciclo completo validado, ponta a ponta

Com os 4 fixes acima, o node provisionado pelo Karpenter **entra de verdade no cluster**:

```
NAME            STATUS   ROLES    AGE   VERSION        INTERNAL-IP
default-bg8zp   Ready    <none>   90s   v1.36.5+k3s1   192.168.15.103
```

E o pod que forçou o provisionamento (que ficava `Pending` antes) é agendado e roda nele normalmente.

**Desprovisionamento também validado, com uma pegadinha a mais**: apagando o pod de teste, o `NodeClaim`
some sozinho (mesmo intervalo de avaliação de antes) e a VM é removida de verdade do Proxmox — mas o
**objeto `Node` do Kubernetes fica órfão, em `NotReady`** (o Karpenter não limpa o lado do k3s, só o lado
do Proxmox). Precisa de `kubectl delete node <nome>` manual. Não precisa de `kubectl drain` antes — a VM
já está fisicamente removida, não há nada "vivo" pra evacuar graciosamente, só um registro no etcd.
