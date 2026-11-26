# Inventário real de componentes — k8s-labs

> Levantado em 2026-11-25 a partir do estado declarado em `terraform/*.tfvars`,
> `ansible/inventory/*.ini` e `manifests/` + `gitops-manifests/`, e **validado contra o
> cluster vivo no mesmo dia** (ambiente religado) via SSH/kubectl direto nos 11 hosts
> (sem depender do MCP do Proxmox, que ficou com a conexão fechada nesta sessão — não é
> um problema do Proxmox em si, API/UI dele respondiam normalmente). Serve de base
> factual para o redesenho dos diagramas de arquitetura e fluxo de entrega.

## 0. Achados da validação ao vivo (2026-11-25)

- Os 2 clusters k3s confirmados `Ready` em todos os nós (k8s-ci: cp+w1+w2; k8s-backstage:
  cp+w1+w2+w3) e os 11 hosts declarados no Terraform todos acessíveis via SSH.
- Namespaces vivos batem com o inventário declarado: `k8s-ci` tem `forgejo`,
  `tekton-pipelines(-resolvers)`; `k8s-backstage` tem `argocd`, `backstage`,
  `cilium-secrets` (confirma CNI Cilium), `dev`/`qa`/`stage`/`prod` (multi-stage,
  namespaces existem mas sem app deployado dentro ainda), `test-app`.
- Argo CD: todas as 4 Applications `Synced`/`Healthy` (`backstage`, `test-app`,
  `multi-stage-namespaces`, `multi-stage-isolation`). Image Updater `READY: True`.
- **Achado real**: o CronJob `renovate` (`manifests/platform-ci/renovate/cronjob.yaml`)
  está com `spec.suspend: true` no cluster vivo, mas o YAML do repo não declara
  `suspend` nenhum -- foi suspenso manualmente fora do Git em algum momento (drift
  declarado vs. vivo), e não está rodando desde então apesar do schedule horário.
  Não revertido ainda -- decisão de quando reativar fica com o Marcio.
- `kube-bench` confirmado suspenso nos dois clusters (`True`), como já documentado.
- **Wazuh**: mesmo gotcha de boot a frio já documentado -- `wazuh-manager` e
  `wazuh-indexer` subiram `failed` (timeout do systemd disputando com o resto do
  boot). Corrigido na mesma ordem já validada (indexer primeiro, manager depois, via
  `systemctl reset-failed` + `start`). RAM em ~47% de uso após o fix (saudável, bate
  com o esperado dos 12GB+heap 4GB ajustados em 24/11). Agentes reconectando
  progressivamente após o Manager voltar (retry automático, sem intervenção manual).

## 1. Infraestrutura (Proxmox / Terraform) — 12 VMs declaradas

| VM | vm_id | IP | vCPU | RAM | Disco | Datastore | Papel |
|---|---|---|---|---|---|---|---|
| k8s-ci-cp | 2021 | .70 | 4 | 8GB | 80GB | data02-thin | k3s server — Forgejo + Tekton |
| k8s-ci-w1 | 2023 | .72 | 4 | 12GB | 120GB | data02-thin | k3s agent |
| k8s-ci-w2 | 2024 | .73 | 4 | 12GB | 120GB | data02-thin | k3s agent |
| nfs-ganesha | 2028 | .77 | 2 | 2GB | 40GB | data02-thin | Storage NFS p/ workspace Tekton (fora do k3s) |
| k8s-backstage-cp | 2022 | .71 | 4 | 8GB | 50GB | DATA | k3s server — Backstage (+Keycloak planejado) |
| k8s-backstage-w1 | 2026 | .75 | 4 | 8GB | 50GB | DATA | k3s agent |
| k8s-backstage-w2 | 2027 | .76 | 4 | 8GB | 50GB | DATA | k3s agent |
| k8s-backstage-w3 | 2029 | .78 | 4 | 8GB | 50GB | DATA | k3s agent (multi-stage) |
| semaphore-ui | 2025 | .74 | 2 | 4GB | 40GB | data02-thin | Orquestração Ansible/Terraform (standalone) |
| ministack | 2007 | .56 | 4 | 4GB | 40GB | data02-thin | Emulador AWS local (standalone) |
| floci-az | 2030 | .79 | 4 | 4GB | 40GB | data02-thin | Emulador Azure local (standalone) |
| wazuh | 2031 | .80 | 8 | 12GB | 100GB | data02-thin | SIEM — Manager+Indexer+Dashboard (standalone) |

**Desprovisionado** (não existe mais, código só na tag git): `k8s-labs-cp/w1/w2`
(2018-2020, .67-.69) — cluster de estudo original "5 pilares", destruído em 2026-11-17,
tag `archive/k8s-labs-5-pilares-2026-11-17`.

## 2. Cluster `k8s-ci` (platform-ci) — CI/CD

k3s via `ansible/roles/k3s-cluster`, gVisor habilitado (Tasks test/sast/sca; **não**
no build-buildah, incompatível). Conteúdo declarado em `manifests/platform-ci/`:

- **Forgejo** (Helm, `forgejo/values.yaml`) — repositório git + registry de imagens.
- **Tekton Pipelines + Triggers + Dashboard** (`tekton/pipelines-release.yaml`,
  `triggers-release.yaml`, `dashboard-release.yaml`).
- **EventListener + TriggerBinding/Templates** (`tekton/shared/`,
  `tekton/backstage-pipeline/trigger-template.yaml`, `tekton/iac-scan/trigger-template.yaml`).
- **Pipeline `backstage-pipeline`**: test → sast (Semgrep) → build (Buildah) →
  sca (Trivy) → sbom (Syft) → image-scan (Trivy) — Tasks efêmeras, não serviços.
- **Pipeline `iac-scan`**: Checkov — dispara por push no repo de infra (k8s-labs),
  não no repo do app.
- **Pipeline `dast-scan`**: OWASP ZAP baseline — hoje disparo manual
  (`pipelinerun.yaml` direto), sem gatilho automático pós-deploy.
- **Renovate** (CronJob) — só fala HTTP com o Forgejo. **Achado 2026-11-25**: está
  `spec.suspend: true` no cluster vivo, drift não declarado no repo (`cronjob.yaml` não
  tem `suspend`) -- suspenso manualmente fora do Git em algum momento, não revertido.
- **kube-bench** (CronJobs x3, suspenso) — audita o control plane/kubelet deste cluster.
- **Pruner** (CronJob) — limpeza de PipelineRuns antigos.
- **RuntimeClass gVisor** + **StorageClass NFS** (via csi-driver-nfs → VM nfs-ganesha).

## 3. Cluster `k8s-backstage` (platform-backstage) — GitOps/Apps

k3s via `ansible/roles/k3s-cluster`, CNI **Cilium** (substituiu Flannel em 2026-11-23,
necessário pra `NetworkPolicy` real). Registry insecure apontando pro Forgejo
(`192.168.15.70:3000`). Conteúdo declarado em `manifests/platform-backstage/` +
repo `gitops-manifests` (consumido via Argo CD):

- **Argo CD** (`argocd/install.yaml`).
- **Applications**: `application-backstage`, `application-test-app`,
  `application-multi-stage-namespaces`, `application-multi-stage-isolation`.
- **Argo CD Image Updater** (CRD `ImageUpdater` v1alpha1) — write-back via Git/SSH
  (`imageupdater-backstage.yaml`, método `git:secret:` com deploy key SSH porta 2222).
- **kube-bench** (CronJobs) — audita este cluster (cópia separada da do k8s-ci).
- **Multi-stage**: namespaces `dev/qa/stage/prod` (`gitops-manifests/platform/multi-stage/namespaces/`)
  + isolamento por estágio — `ResourceQuota`/`LimitRange`/`NetworkPolicy`
  (`gitops-manifests/platform/multi-stage/isolation/`), validado com testes de rede reais.
- **App `backstage`** (`gitops-manifests/apps/backstage/base/`): Deployment + Postgres
  (Deployment+PVC+Service) + Service + Ingress.
- **App `test-app`** (`gitops-manifests/apps/test-app/base/`): Deployment + Service.

## 4. VMs standalone (fora de qualquer cluster k3s)

| VM | Papel | Observação |
|---|---|---|
| semaphore-ui | UI de execução Ansible/Terraform | Deliberadamente fora de qualquer automação que ela mesma dispare |
| ministack | Emulador AWS (Lambda/SQS/DynamoDB/S3) | Alvo de validação do Crossplane (MiniStack provider, **ainda não implementado**) |
| floci-az | Emulador Azure | Bloqueado pro Crossplane oficial (providers Upjet só falam ARM real) — alternativa `provider-http` avaliada, pendente docs da API |
| wazuh | SIEM — Manager+Indexer+Dashboard v4.14 | Agente Ansible em todos os 11 hosts do lab; SCA ativo (vai substituir o Lynis após validação) |
| nfs-ganesha | Storage NFS pro workspace Tekton | Consumido via csi-driver-nfs pelo k8s-ci; não roda k3s |

## 5. Pendente / planejado (não implementado ainda)

- **Crossplane** — decidido co-localizar com Argo CD em `k8s-backstage` (mecanismo de
  sync-wave Claim→Secret→Deployment); nada instalado ainda.
- **Keycloak** — SSO do Backstage; não instalado.
- **Namespace `platform-tools`** em `k8s-ci` (Renovate + kube-bench) — planejado em
  2026-11-24, sem `NetworkPolicy`/gVisor por decisão explícita, não implementado.
- **Gatilho automático do DAST** pós-sync do Argo CD — hoje manual.
- **Longhorn → Velero → Kyverno enforcement → Prometheus/Grafana → cert-manager → Falco**
  — sequência de estudo definida (2026-11-21/24), não iniciada (Longhorn em fase de leitura).
- **Lynis** — ainda ativo via Ansible/Semaphore em todos os hosts; só será desligado
  depois de validar o SCA do Wazuh contra o baseline (62/100).

## 6. Fora de escopo deste levantamento

Validado o essencial (nós, namespaces, Applications, CronJobs, serviços systemd) via
SSH/kubectl em 2026-11-25. Não verificado em detalhe: versões exatas de todos os Helm
charts instalados, estado interno de cada Pod além do que já foi listado acima.
