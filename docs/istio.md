# Istio no k8s-labs — instalação e 4 cenários de troubleshooting

Quarto pilar do `k8s-labs` (depois de Kustomize, KEDA e Karpenter). Istio
**1.31.3** em modo **sidecar**, instalado no cluster existente (3 nodes k3s
v1.36.5). Tudo validado ponta a ponta em 2026-10-23; cada cenário foi
quebrado, diagnosticado, corrigido e **revertido** (fixtures prontos pra
reuso).

```
manifests/istio/
├── install/istio-operator.yaml              # IstioOperator (profile minimal)
├── base/workloads.yaml                      # ns istio-lab, httpbin v1/v2, cliente curl
├── scenario-1-mtls-strict/                  # PeerAuthentication STRICT x cliente sem sidecar
├── scenario-2-canary-subset/                # canary 80/20 com subset que não seleciona pods
├── scenario-3-retry-masking/                # retries/perTryTimeout escondendo falha e lentidão
└── scenario-4-outlier-ejection/             # outlier detection ejetando pods saudáveis
```

Atalhos usados no guia (cole no shell antes de começar):

```bash
cd ~/k8s-labs
alias k='kubectl --context k8s-labs'
alias ic='istioctl --context k8s-labs'
# dispara N requisições do pod cliente e agrega por status HTTP
hits() { n=$1; url=$2; for i in $(seq 1 $n); do
  k -n istio-lab exec deploy/curl -c curl -- curl -s -o /dev/null -w '%{http_code}\n' "$url"
done | sort | uniq -c; }
```

> **Rode um cenário por vez.** Os cenários 2, 3 e 4 criam `VirtualService`/
> `DestinationRule` com o mesmo nome (`httpbin`) — aplicar dois juntos
> sobrescreve um com o outro.

---

## Passo 0 — Recursos dos nodes

Os nodes tinham 2 vCPU / 4GB. O Istio em sidecar custa um istiod (~256Mi+)
**mais um Envoy por pod**. Antes de instalar, a RAM dos **workers** subiu de
4GB → **6GB** pela IaC (não pela UI do Proxmox):

```bash
# terraform/cluster/terraform.tfvars: k8s-labs-w1 e k8s-labs-w2 -> memory = 6144
cd terraform/cluster
terraform plan     # Plan: 0 to add, 2 to change, 0 to destroy (update in-place)
terraform apply
```

`terraform plan` mostrou só `memory.dedicated 4096 -> 6144` nas duas VMs. Os
workers estavam desligados, então a mudança entrou no próximo boot (`qm start
2019 2020`). O control plane ficou com 4GB — o istiod acabou agendado num
worker de qualquer forma.

> As variáveis `PROXMOX_VE_*` vivem no `.bashrc`; um `bash -c` não-interativo
> não as carrega (`Error: Missing Proxmox VE API Endpoint`). Rodar de um shell
> interativo normal.

## Passo 1 — istioctl e pré-checagem

```bash
mkdir -p ~/istio-dl && cd ~/istio-dl
curl -sLO https://github.com/istio/istio/releases/download/1.31.3/istio-1.31.3-linux-amd64.tar.gz
curl -sLO https://github.com/istio/istio/releases/download/1.31.3/istio-1.31.3-linux-amd64.tar.gz.sha256
sha256sum -c istio-1.31.3-linux-amd64.tar.gz.sha256      # OK
tar xzf istio-1.31.3-linux-amd64.tar.gz
cp istio-1.31.3/bin/istioctl ~/.local/bin/
istioctl version --remote=false                           # client version: 1.31.3
istioctl --context k8s-labs x precheck
# ✔ No issues found when checking the cluster. Istio is safe to install or upgrade!
```

**Por que 1.31.x**: linha estável mais nova no dia (1.32 ainda em beta). Com
o k8s 1.36 bem recente, o `precheck` é a confirmação prática de
compatibilidade — a mesma lição do Karpenter (versão antiga + K8s novo =
panic). O tarball também traz `samples/`, de onde vieram as imagens
pinadas (`go-httpbin:v2.15.0`, `curl:8.16.0`).

## Passo 2 — Instalar o control plane

```bash
ic install -f manifests/istio/install/istio-operator.yaml -y
# ✔ Istio core installed ⛵️
# ✔ Istiod installed 🧠
# ✔ Installation complete
k -n istio-system get pods        # istiod-...  1/1 Running
```

Decisões do `istio-operator.yaml`:

| Escolha | Por quê |
|---|---|
| `profile: minimal` (só istiod) | Cenários são todos leste-oeste (pod→pod). Um ingress gateway `LoadBalancer` brigaria com o Traefik do k3s pelas portas 80/443 no ServiceLB. |
| istiod `requests 100m/256Mi`, HPA desligado | Default pede 500m/2Gi — desproporcional pra nodes de 2 vCPU. |
| sidecar `requests 10m/40Mi` | Default é 100m/128Mi **por pod**; em lab isso esgota o node antes da aplicação. |
| `meshConfig.accessLogFile: /dev/stdout` | Access log do Envoy em cada sidecar. É a principal ferramenta dos cenários (campo *response flags*: `UH`, `UT`, `URX`, `DC`). |

## Passo 3 — App base

```bash
k apply -f manifests/istio/base/workloads.yaml
k -n istio-lab wait --for=condition=Available deploy --all --timeout=240s
k -n istio-lab get pods
# curl-...          2/2  Running     <- 2/2 = app + istio-proxy (sidecar injetado)
# httpbin-v1-... x2 2/2  Running
# httpbin-v2-...    2/2  Running
```

O namespace tem `istio-injection: enabled`: o webhook do istiod injeta o
container `istio-proxy` em todo pod criado ali. Um único `Service httpbin`
seleciona v1 e v2 (`app: httpbin`); o label `version` só importa quando um
`DestinationRule` define subsets.

Sanidade (sem nenhuma regra Istio, balanceamento round-robin do Envoy):

```bash
for i in $(seq 1 12); do k -n istio-lab exec deploy/curl -c curl -- curl -s httpbin:8000/hostname; echo; done | sort | uniq -c
#  5 httpbin-v1-...-8ssvk
#  4 httpbin-v1-...-c5tsv
#  3 httpbin-v2-...-7c6sz
```

Endpoints do go-httpbin usados nos cenários: `/hostname` (qual pod
respondeu), `/delay/N` (responde após N s), `/status/200:1,503:1` (sorteia
200 ou 503 com peso), `/status/500`.

---

## Cenário 1 — mTLS STRICT quebrando cliente sem sidecar

**História**: o time de segurança liga mTLS obrigatório no namespace. Um
consumidor que ainda não migrou pro mesh para de funcionar.

```bash
S=manifests/istio/scenario-1-mtls-strict
k apply -f $S/legacy-client.yaml        # ns "legacy" SEM injeção + pod curl
k -n legacy exec deploy/curl -- curl -s -o /dev/null -w '%{http_code}\n' httpbin.istio-lab:8000/get
# 200     <- default do Istio é PERMISSIVE (aceita mTLS e texto puro)
k apply -f $S/peer-authentication.yaml  # mode: STRICT
```

**Sintoma**:

```bash
k -n legacy exec deploy/curl -- curl -sS httpbin.istio-lab:8000/get
# curl: (56) Recv failure: Connection reset by peer
k -n istio-lab exec deploy/curl -c curl -- curl -s -o /dev/null -w '%{http_code}\n' httpbin:8000/get
# 200     <- quem tem sidecar continua funcionando
```

**Diagnóstico**:

```bash
POD=$(k -n istio-lab get pod -l app=httpbin,version=v1 -o jsonpath='{.items[0].metadata.name}')
ic x describe pod $POD.istio-lab
# Effective PeerAuthentication:
#    Workload mTLS mode: STRICT
# Applied PeerAuthentication:
#    default.istio-lab
```

**Achado importante — a falha é invisível no access log.** O reset acontece
no handshake, antes de existir requisição HTTP, então o access log do
httpbin não mostra nada. As stats padrão também não ajudam (o Istio só expõe
um subconjunto das stats do Envoy; um diff antes/depois não mudou nenhum
contador relevante). O que mostra a causa é subir o log **só** dos loggers de
conexão:

```bash
ic proxy-config log $POD.istio-lab --level conn_handler:debug,filter:debug
# (gerar a falha de novo pelo cliente legacy)
k -n istio-lab logs $POD -c istio-proxy --since=20s | grep -E 'tls inspector|filter chain'
# tls inspector: parseClientHello failed: ... SSL routines:OPENSSL_internal:HTTP_REQUEST
# closing connection from 10.42.1.59:34976: no matching filter chain found
ic proxy-config log $POD.istio-lab --level conn_handler:warning,filter:warning   # voltar
```

Leitura: o listener inbound (`15006`) usa o *tls_inspector* pra escolher a
filter chain. Em STRICT só existe a chain TLS; chegou um `GET` em texto puro
(`HTTP_REQUEST` onde se esperava um ClientHello) → nenhuma chain casa → o
Envoy fecha a conexão → o cliente vê *connection reset*.

**Correções** (as duas validadas):

```bash
# A) transição: PERMISSIVE enquanto os consumidores migram -> legacy volta a 200
# B) definitiva: trazer o consumidor pro mesh
k label ns legacy istio-injection=enabled --overwrite
k -n legacy rollout restart deploy/curl
k -n legacy exec deploy/curl -c curl -- curl -s -o /dev/null -w '%{http_code}\n' httpbin.istio-lab:8000/get
# 200   <- agora com mTLS de ponta a ponta, mesmo com STRICT
```

**Reverter**: `k delete -f $S/peer-authentication.yaml -f $S/legacy-client.yaml`

---

## Cenário 2 — Canary com subset que não seleciona nenhum pod

**História**: canary 80/20 da v2. Alguém reporta "o canary está dando ~20% de
503, faz rollback da v2!". Mas a v2 está saudável.

```bash
S=manifests/istio/scenario-2-canary-subset
k apply -f $S/traffic.yaml      # DestinationRule (subsets v1/v2) + VirtualService 80/20
hits 50 httpbin:8000/get
#  37 200
#  13 503
```

**Diagnóstico** — em ordem do mais barato pro mais profundo:

```bash
ic analyze -n istio-lab
# Error [IST0173] (DestinationRule istio-lab/httpbin) The Subset v2 defined in the
# DestinationRule does not select any pods. Which may lead to 503 UH (NoHealthyUpstream).

CURL=$(k -n istio-lab get pod -l app=curl -o jsonpath='{.items[0].metadata.name}')
k -n istio-lab logs $CURL -c istio-proxy | grep ' 503 ' | tail -1
# "GET /get HTTP/1.1" 503 UH no_healthy_upstream ... outbound|8000|v2|httpbin.istio-lab.svc.cluster.local

ic proxy-config endpoints $CURL.istio-lab --cluster 'outbound|8000|v2|httpbin.istio-lab.svc.cluster.local'
# ENDPOINT     STATUS     OUTLIER CHECK     CLUSTER        <- vazio!
k -n istio-lab get pods -l app=httpbin -L version
# ... VERSION v1, v1, v2   <- o pod é "v2"; o subset pede "V2"
```

Leitura: cada subset vira um **cluster Envoy próprio**
(`outbound|8000|v2|httpbin...`). Label selector é case-sensitive; `V2` ≠
`v2` → cluster sem endpoints → os 20% roteados pra ele saem `503 UH` direto
do sidecar do **cliente**, sem nunca chegar à v2. Note o `"-"` no campo de
upstream do access log: nenhum pod foi contatado.

**Correção**: `version: v2` no subset.

```bash
hits 50 httpbin:8000/get                       # 50 200
for i in $(seq 1 50); do k -n istio-lab exec deploy/curl -c curl -- curl -s httpbin:8000/hostname | grep -o 'v[12]'; done | sort | uniq -c
#  44 v1
#   6 v2      <- ~88/12, dentro do ruído de 50 amostras pra 80/20
```

Lição extra: com o VirtualService, o peso é independente do número de
réplicas (a v2 tem 1 de 3 pods, mas recebe 20%, não 33%).

**Reverter**: `k delete -f $S/traffic.yaml`

---

## Cenário 3 — Retry e timeout mascarando um backend doente

**História**: uma política de resiliência "generosa" (`attempts: 3`,
`perTryTimeout: 500ms`, `retryOn: 5xx,...`). O dashboard do consumidor está
verde. O backend não está.

```bash
S=manifests/istio/scenario-3-retry-masking
k apply -f $S/virtualservice.yaml
```

### 3a) Falha mascarada

```bash
hits 40 'httpbin:8000/status/200:1,503:1'      # backend falha ~50%
#  39 200
#   1 503
```

O cliente vê 97,5% de sucesso. A métrica padrão do Istio é reportada pelos
**dois lados** (`reporter="source"` no cliente, `reporter="destination"` no
servidor), e é aí que aparece a verdade:

```bash
for P in $(k -n istio-lab get pod -l app=httpbin -o name | cut -d/ -f2); do
  k -n istio-lab exec $P -c istio-proxy -- pilot-agent request GET stats/prometheus \
    | grep '^istio_requests_total' | grep 'reporter="destination"' | grep 'response_code="503"'
done
# (diferença antes/depois das 40 requisições) -> 33 respostas 503 no SERVIDOR
```

40 chamadas do cliente viraram ~73 no backend: o retry escondeu 33 falhas e
quase dobrou a carga.

### 3b) Lentidão virando erro (retry storm)

```bash
k -n istio-lab exec deploy/curl -c curl -- curl -s -o /dev/null -w 'code=%{http_code} tempo=%{time_total}s\n' httpbin:8000/delay/1
# code=504 tempo=2.04s     <- uma chamada que funcionaria em 1s
```

Correlacionando pelo `x-request-id` (o Envoy gera e propaga):

```
cliente : "GET /delay/1" 504 URX,UT upstream_per_try_timeout ... 2102ms  id=14aa607a...
httpbin-v1-8ssvk : 0 DC downstream_remote_disconnect  502ms  id=14aa607a...
httpbin-v2-7c6sz : 0 DC downstream_remote_disconnect  501ms  id=14aa607a...
httpbin-v1-c5tsv : 0 DC downstream_remote_disconnect  504ms  id=14aa607a...
httpbin-v1-8ssvk : 0 DC downstream_remote_disconnect  502ms  id=14aa607a...
```

Leitura das flags: `UT` = timeout (por tentativa), `URX` = limite de retries
esgotado; do lado do servidor, `DC` = o cliente (o sidecar) desconectou —
cada tentativa foi cortada aos 500ms, antes do backend responder em 1s. Um
mesmo request id em **4 pods** é a assinatura de retry.

**Correção** — retry só onde é seguro e timeout coerente com a latência real:

```yaml
http:
  - route: [{destination: {host: httpbin}}]
    timeout: 3s
    retries: {attempts: 1, perTryTimeout: 2s, retryOn: "reset,connect-failure"}
```

```bash
hits 40 'httpbin:8000/status/200:1,503:1'   # 18 200 / 22 503  <- o problema real agora aparece
# /delay/1 -> code=200 tempo=1.00s
```

A "piora" do 3a depois da correção é o ponto: o 503 é do backend e precisa
ser corrigido lá; retry em `5xx` de aplicação só adia a descoberta (e
multiplica carga). Retry é seguro para falhas de transporte
(`reset`, `connect-failure`) e operações idempotentes.

**Reverter**: `k delete -f $S/virtualservice.yaml`

---

## Cenário 4 — Outlier detection ejetando pods saudáveis

**História**: alguém configura circuit breaker "pra tirar do pool rápido
qualquer pod com problema". Um cliente começa a mandar requisições inválidas
(a app devolve 500 de negócio). O serviço inteiro cai — inclusive pra quem só
chama `/get`.

```bash
S=manifests/istio/scenario-4-outlier-ejection
k apply -f $S/destinationrule.yaml   # consecutive5xxErrors: 1, baseEjectionTime: 3m, maxEjectionPercent: 100
hits 10 httpbin:8000/get             # 10 200
hits 6  httpbin:8000/status/500      # 6 500   (o "cliente ruim")
hits 10 httpbin:8000/get             # 10 503  (todo mundo)
```

**Diagnóstico**:

```bash
ic proxy-config endpoints $CURL.istio-lab --cluster 'outbound|8000||httpbin.istio-lab.svc.cluster.local'
# ENDPOINT          STATUS    OUTLIER CHECK   CLUSTER
# 10.42.1.52:8080   HEALTHY   FAILED          outbound|8000||httpbin...
# 10.42.1.53:8080   HEALTHY   FAILED          ...
# 10.42.2.81:8080   HEALTHY   FAILED          ...
k -n istio-lab logs $CURL -c istio-proxy --tail=1
# "GET /get HTTP/1.1" 503 UH no_healthy_upstream
k -n istio-lab get pods -l app=httpbin    # todos 2/2 Running, 0 restarts
```

Leitura: `STATUS HEALTHY` (Kubernetes/EDS diz que o pod está bom) **e**
`OUTLIER CHECK FAILED` (o Envoy do cliente ejetou por conta própria). Outlier
detection é **passivo e local a cada cliente**: nenhum probe falhou, nenhum
pod reiniciou — por isso `kubectl` mostra tudo verde. Com `consecutive5xxErrors:
1` um único 500 ejeta o pod; com `maxEjectionPercent: 100` nada impede de
ejetar o pool todo → mesmo `503 UH` do Cenário 2, causa completamente
diferente (aqui o cluster tem endpoints, só estão todos ejetados).

**Correção** — contar só erro de infraestrutura, com limites:

```yaml
outlierDetection:
  consecutiveGatewayErrors: 5   # 502/503/504 = pod/conexão com problema
  consecutive5xxErrors: 0       # 500 de aplicação não ejeta ninguém
  interval: 10s
  baseEjectionTime: 30s
  maxEjectionPercent: 50        # nunca ejetar mais da metade do pool
```

```bash
hits 6 httpbin:8000/status/500   # 6 500
hits 10 httpbin:8000/get         # 10 200
# proxy-config endpoints -> OUTLIER CHECK OK nos 3
```

**Reverter**: `k delete -f $S/destinationrule.yaml`

---

## Mapa rápido de response flags (vistos nos cenários)

| Flag | Onde apareceu | Significa |
|---|---|---|
| `UH` | Cenários 2 e 4 | No healthy upstream — cluster sem endpoint utilizável (vazio *ou* todos ejetados) |
| `UT` | Cenário 3 | Upstream request timeout (aqui, por tentativa) |
| `URX` | Cenário 3 | Limite de retries atingido |
| `DC` | Cenário 3 (servidor) | Downstream connection termination — quem chamou desistiu |
| *(nenhum log)* | Cenário 1 | Falha antes do HTTP (handshake/filter chain) — ver logs `conn_handler` |

## Desinstalar

```bash
k delete -f manifests/istio/base/workloads.yaml
ic uninstall --purge -y
k delete ns istio-system
```

## Gotchas encontrados na implementação

1. `bash -c` não-interativo não carrega `.bashrc` → Terraform sem
   `PROXMOX_VE_*`. Usar shell interativo (`bash -ic`).
2. Stats do Envoy: o Istio expõe só um subconjunto por padrão; não espere
   achar todo contador do Envoy em `pilot-agent request GET stats`. Para
   falhas de conexão, log level por logger (`proxy-config log`) é mais
   rápido. Para contagem de requisições, `istio_requests_total` com os dois
   `reporter`s.
3. O access log de uma requisição do cliente pode demorar ~1s pra aparecer
   (buffer de flush do Envoy) — esperar antes de concluir que "não logou".
