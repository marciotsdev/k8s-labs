# Karpenter contra o MiniStack — resultado real do teste

> **Abordagem abandonada em favor do [provider Proxmox](karpenter-proxmox.md)**, que funciona de
> verdade (provisiona VMs reais no lab). Este documento fica como registro do achado real — o
> provider **AWS** do Karpenter não consegue nem inicializar contra o MiniStack — não como guia a
> seguir.

Karpenter não é um autoscaler genérico: ele fala diretamente com a API EC2 de
um provedor de nuvem para criar/destruir instâncias reais. Neste homelab não
existe nuvem real — a aposta foi apontá-lo para o **MiniStack** (emulador AWS
já usado pelo Crossplane em `homelab-gitops`), via a variável padrão do AWS
SDK v2 `AWS_ENDPOINT_URL` no processo do controller.

## O que foi testado

1. CoreDNS com wildcard pra `ministack.homelab` (mesmo padrão do Crossplane).
2. Bootstrap de um IAM role + instance profile fake no MiniStack (ele não
   valida credenciais, mas a chamada em si precisa ter uma resposta).
3. Karpenter v1.15.0 (precisa ser >= 1.13 pra ser compatível com K8s 1.36,
   que é o que o k3s "stable" instalou) instalado via Helm, env apontando
   pro MiniStack com credenciais fake (`test`/`test`).
4. Tentativa de contornar com `settings.isolatedVPC=true` (pensado pra VPCs
   sem saída de internet — parecia o fit certo).

## Resultado: o controller nem chega a subir

```
panic: describing instance type zone offerings, operation error EC2:
DescribeInstanceTypeOfferings, https response error StatusCode: 400,
api error InvalidAction: Unknown EC2 action: DescribeInstanceTypeOfferings
```

No boot (`operator.go`, dentro de `NewOperator`), o controller chama
`DescribeInstanceTypeOfferings` **incondicionalmente**, antes de processar
qualquer `NodePool` ou `NodeClaim`. `settings.isolatedVPC=true` não pula essa
chamada especificamente (só afeta lookups de pricing) — testado e confirmado
neste cluster, não é só leitura de changelog.

A edição "light"/community do MiniStack (equivalente ao LocalStack
community) simplesmente **não implementa essa action da API EC2** — responde
`InvalidAction`. Resultado: o pod entra em `CrashLoopBackOff` permanente,
sem nunca chegar a tentar um `RunInstances`.

Isso é mais restritivo do que a hipótese original (que esperava o controller
subir e ficar preso num `NodeClaim` nunca-registrado). Na prática, o teto de
compatibilidade do MiniStack community com a API EC2 real do Karpenter é mais
baixo do que isso — ele cobre bem S3/DynamoDB/SQS/IAM básico (o suficiente
pro Crossplane), mas não as chamadas de descoberta que o Karpenter precisa
só pra inicializar.

## Estado final deixado no cluster

- O **Helm release continua instalado** e os **CRDs** (`NodePool`,
  `EC2NodeClass`, `NodeClaim`) estão disponíveis pra inspeção
  (`kubectl get crd | grep karpenter`, `kubectl explain nodepool`) — dá pra
  estudar a API sem o controller rodando.
- O **Deployment está escalado para 0 réplicas** (`kubectl -n karpenter
  scale deploy/karpenter --replicas=0`) de propósito, pra não ficar gerando
  `CrashLoopBackOff` sem parar.

## Se quiser ir além

Validar autoscaling de nó de verdade exigiria algo com cobertura real da API
EC2 (ex.: LocalStack Pro, que também roda a instância como container Docker
local) ou simplesmente um provedor de nuvem real. Sem isso, o teto de
aprendizado aqui é: arquitetura do Karpenter, CRDs, mecânica de chamada de
API, e — isso em si — **diagnosticar por que um controller terceirizado
falha contra uma implementação parcial de uma API que ele assume como
completa**. Esse diagnóstico (ler o panic, identificar a action exata que
falhou, confirmar no provedor que ela não existe) é uma habilidade real de
troubleshooting, só que descoberta antes da etapa que o teste original
esperava validar.
