# Postgres HA — trilha de fundamentos

> Pra quem já é sênior em infra/Kubernetes mas não tem atuação prática nesse nível de banco de
> dados. Cada seção explica um conceito do zero e termina com um comando real pra rodar contra o
> cluster `postgres-shared-1/2/3` (já implementado, ver `terraform/postgres-cluster/` e
> `ansible/roles/postgres-cluster/`) — a ideia é ver o mecanismo acontecendo, não só ler sobre ele.

## 0. O problema que estamos resolvendo

Um banco de dados roda num processo só, guardando dado em disco. Se essa máquina cair, o dado para
de existir até alguém religar — e se o disco morreu junto, o dado já era. "HA de banco" é a soma de
duas coisas bem diferentes que é fácil confundir:

- **Durabilidade**: o dado sobrevive a uma falha (backup, réplica).
- **Disponibilidade**: o serviço continua respondendo mesmo com uma falha (failover automático).

O Forgejo hoje (SQLite) não tem nenhuma das duas. O cluster que montamos resolve as duas ao mesmo
tempo: 3 cópias completas do dado (durabilidade) + promoção automática de uma réplica pra líder se
o atual cair (disponibilidade).

## 1. WAL — o mecanismo central de tudo

**O que é**: antes de qualquer mudança chegar na tabela de verdade, o Postgres escreve um registro
dela num arquivo sequencial chamado **WAL** (Write-Ahead Log — "log escrito antes"). Só depois de
gravar no WAL é que a mudança é aplicada nas páginas de dado em si (e isso pode acontecer bem
depois, de forma preguiçosa).

**Por que existe**: se a máquina cair no meio de uma escrita, o Postgres reconstrói o estado
correto relendo o WAL desde o último ponto seguro (checkpoint) — é o que garante que uma
transação confirmada (`COMMIT`) nunca se perde, mesmo que a página de dado em disco ainda não
tivesse sido atualizada na hora da queda.

**A sacada pra HA**: se o WAL descreve *toda* mudança que acontece no banco, em ordem, então
mandar esse mesmo fluxo de bytes pra outra máquina e deixar ela "reproduzir" é o suficiente pra
manter uma cópia idêntica, atualizada quase em tempo real. É exatamente isso que streaming
replication faz — não existe mágica nova, é reaproveitar o mesmo mecanismo que já protege contra
queda.

**Ver de verdade**:
```bash
ssh ubuntu@192.168.15.81 'sudo -u postgres psql -c "SELECT pg_current_wal_lsn();"'
```
Isso mostra a posição atual do WAL (um "endereço" tipo `0/4000148` — o mesmo número que apareceu
no `Receive LSN`/`Replay LSN` do `patronictl list`). Roda de novo depois de criar uma tabela
qualquer e repara que o número sobe — cada mudança avança essa posição.

## 2. Replicação em streaming

**O mecanismo**: cada réplica (`postgres-shared-2` e `-3`) abre uma conexão permanente com o líder
e pede "me manda o WAL a partir desse ponto". O processo do lado do líder que atende isso chama
`walsender` — você já viu ele no `systemctl status patroni` (`walsender replicator ... streaming`).
Do lado da réplica, um processo recebe e aplica esse WAL continuamente.

**Síncrona vs. assíncrona** (configuração que ainda não setamos explicitamente — hoje é assíncrona
por default): numa réplica **assíncrona**, o líder confirma a transação pro cliente sem esperar a
réplica confirmar que recebeu — mais rápido, mas se o líder morrer no instante exato entre o
commit local e a réplica receber, essa última transação pode se perder no failover. Numa réplica
**síncrona**, o líder espera pelo menos uma réplica confirmar antes de dar o commit como concluído
— mais seguro, mais lento.

**Ver de verdade**:
```bash
ssh ubuntu@192.168.15.81 'sudo -u postgres psql -c "SELECT application_name, state, sync_state FROM pg_stat_replication;"'
```
O `sync_state` vai mostrar `async` pras duas réplicas — é o que já temos hoje, por decisão
implícita (não configuramos nada diferente). Fica registrado como ponto de evolução futura.

## 3. Consenso distribuído — por que 3 nós, nunca 2

**O problema do "split-brain"**: se você tem só 2 nós e a rede entre eles cai (mas os dois
continuam vivos individualmente), cada um pode achar que é o único sobrevivente e se promover a
líder sozinho — agora você tem **dois líderes** aceitando escrita ao mesmo tempo, e os dados
divergem sem ninguém perceber até ser tarde.

**A solução — quorum**: com um número ímpar de "votantes" (3, no nosso caso), uma decisão só é
válida se **mais da metade** concordar (2 de 3). Se a rede particiona o cluster em um grupo de 1 e
outro de 2, só o grupo de 2 tem quorum pra eleger um líder — o nó isolado sozinho sabe que não tem
maioria e se recusa a virar líder. Isso é o que impede o split-brain.

**Onde isso mora no nosso cluster**: não é o Postgres nem o Patroni quem implementa esse algoritmo
de consenso — é o **etcd**, rodando como um processo separado nos mesmos 3 nós
(`ansible/roles/postgres-cluster/templates/etcd.conf.j2`). O etcd usa um algoritmo chamado **Raft**
pra isso.

## 4. etcd como DCS (Distributed Consensus Store)

**O que ele guarda de verdade**: não é o dado do Postgres — é só um pequeno registro tipo
chave-valor com metadados do cluster: quem é o líder agora, até quando esse "contrato de liderança"
(leader lease) é válido, e o estado de configuração do Patroni. Pense nele como um "quadro de avisos
confiável" que os 3 nós consultam e disputam.

**O mecanismo do lease**: o líder precisa renovar seu "direito de ser líder" no etcd periodicamente
(a cada poucos segundos). Se ele parar de renovar — porque caiu, travou, ou perdeu rede — o lease
expira sozinho, e os outros nós percebem que o cargo está livre e disputam a eleição de novo.
Ninguém "detecta a queda" diretamente; todo mundo só observa que o lease não foi renovado.

**Ver de verdade**:
```bash
ssh ubuntu@192.168.15.81 'sudo ETCDCTL_API=3 etcdctl get /service/postgres-lab/leader'
```
Isso mostra literalmente o registro no etcd que diz quem é o líder agora — é esse valor que o
Patroni de cada nó está checando o tempo todo.

## 5. Patroni — o agente que decide e age

**O que ele realmente é**: um processo Python que roda em cada nó, lado a lado com o Postgres, e
faz 3 coisas: (1) consulta o etcd pra saber o estado do cluster, (2) decide se este nó deve ser
líder, réplica, ou precisa de alguma ação (promover, rebaixar, reconfigurar), e (3) **controla o
processo do Postgres diretamente** (start/stop/promote) — é por isso que mascaramos o
`postgresql.service` nativo (`ansible/roles/postgres-cluster/tasks/main.yml`, task "Mask the
generic postgresql systemd service") — se o systemd também tentasse gerenciar o Postgres, os dois
"donos" brigariam.

**O mecanismo de failover, passo a passo**: líder para de renovar o lease (caiu) → lease expira no
etcd → as réplicas percebem, numa próxima consulta → elas disputam escrever "sou eu o novo líder"
no etcd → só uma consegue (é o próprio etcd, via Raft, quem garante que só uma escrita vence) → o
Patroni dessa réplica vencedora executa `pg_ctl promote` no Postgres local → o HAProxy, consultando
o endpoint `/primary` do Patroni (`templates/haproxy.cfg.j2`), já enxerga o novo líder na próxima
checagem de saúde (a cada poucos segundos) e passa a rotear escrita pra ele.

**Ver de verdade — o teste mais importante desta trilha** (failover real, não simulado):
```bash
ssh ubuntu@192.168.15.81 'sudo systemctl stop patroni'
```
Espera uns 15-20 segundos e roda, de qualquer um dos outros dois nós:
```bash
ssh ubuntu@192.168.15.82 'sudo -u postgres patronictl -c /etc/patroni/patroni.yml list'
```
Você deve ver `postgres-shared-2` ou `postgres-shared-3` virar o novo `Leader`, e o
`postgres-shared-1` (quando religar) voltar como `Replica`. Depois religa ele:
```bash
ssh ubuntu@192.168.15.81 'sudo systemctl start patroni'
```

## 6. Memória do Postgres — o que cada parâmetro guarda de verdade

- **`shared_buffers`** — um pedaço de memória compartilhada entre TODOS os processos do Postgres,
  usado como cache de páginas de dado lidas do disco. Configuramos 25% da RAM (regra padrão da
  documentação oficial, ver `bootstrap.dcs.postgresql.parameters` em `templates/patroni.yml.j2`).
- **`work_mem`** — memória que **cada operação de ordenação/hash dentro de uma query** pode usar
  antes de precisar gravar resultado intermediário em disco (mais lento). É por conexão/operação,
  não global — por isso configurar um valor alto num servidor com muitas conexões simultâneas pode
  estourar a RAM total rapidinho (é multiplicativo, não fixo).
- **`maintenance_work_mem`** — parecido com o `work_mem`, mas só pra operações de manutenção
  (`VACUUM`, criação de índice) — pode ser mais generoso porque poucas rodam ao mesmo tempo.

**Ver de verdade**:
```bash
ssh ubuntu@192.168.15.81 'sudo -u postgres psql -c "SHOW shared_buffers;" -c "SHOW work_mem;"'
```

## Próximos passos desta trilha (quando quiser aprofundar mais)

- Configurar replicação **síncrona** numa das réplicas e observar o impacto real de latência.
- Provocar uma partição de rede de propósito (ex. `iptables` bloqueando um nó) e ver o
  comportamento de quorum na prática, não só failover por processo parado.
- Migrar o Forgejo de verdade pro cluster (próximo passo já registrado como pendente) e observar o
  `pg_stat_replication` com carga real em vez de um banco vazio.
