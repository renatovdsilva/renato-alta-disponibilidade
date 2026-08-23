# 11 — Métricas registadas

Só números medidos. Nada estimado. É daqui que saem os bullets do currículo.

Células vazias são medições que ainda não foram feitas — ficam vazias de
propósito, e não preenchidas por aproximação.

---

## Imagens Docker

| Aplicação | Baseline | Otimizada | Redução | Tempo de build |
|---|---|---|---|---|
| quinta-calvario | **3,4 GB** | **282 MB** | **92%** (12×) | ~54 s com cache |
| briosa-agenda | | | | |

**Quinta — detalhe (11/08/2026):**

| Item | Valor |
|---|---|
| Baseline | single-stage, `node:20` (Debian), `node_modules` completo |
| Otimizada | multi-stage, `node:20-alpine`, bundle `standalone`, `.dockerignore` |
| `npm run build` | 26,7 s |
| `npx prisma generate` | 2,0 s |
| `package-lock.json` | 35 862 bytes, 81 pacotes |

A redução vem, por ordem de peso: separar build de runtime, trocar a base
Debian por Alpine, e impedir que `node_modules` e `.next` locais entrem no
contexto de build.

---

## Cluster

| Métrica | Valor |
|---|---|
| Nós | 3 (1 control plane + 2 workers) |
| Versão do Kubernetes | v1.35.5+k3s1 |
| Tempo de criação do cluster | ~75 s |
| Ingress NGINX pronto | ~76 s |
| Namespaces aplicacionais | 2 (`quinta`, `briosa`) |
| Aplicações em execução | 1 (Quinta do Calvário, 2 réplicas em nós diferentes) |
| `k3d image import` para os 3 nós | 6 s |
| RAM consumida em repouso | |
| Tempo de bootstrap do zero | |

---

## Bases de dados

| Métrica | Valor |
|---|---|
| PostgreSQL (Quinta) | 16.14 Alpine, `postgres-0` `1/1 Running` |
| PVC | `data-postgres-0` · `Bound` · 2 Gi · RWO · `local-path` |
| MySQL (Briosa) | *(por aplicar)* |

---

## Disponibilidade

| Teste | Resultado |
|---|---|
| Recuperação do pod da base de dados (`delete pod` → `Ready`) | **6 s** — `Running` aos 2 s, `Ready` aos 6 s |
| Persistência dos dados após destruição do pod | **total** — nenhuma perda |
| **Quedas de energia reais** (12/08 e 14/08/2026, sem encerramento ordenado) | **2 ocorrências, 2 recuperações autónomas**, ~5 min até todos os pods `Running`, **zero intervenção manual**, dados intactos nas duas |
| Estabilidade do cluster antes da queda | 38 h contínuas, 3 nós `Ready`, sem falhas |
| Self-heal do ArgoCD (`scale` manual → reposto) | **1–2 s** — as réplicas extra nunca chegaram a materializar-se |
| Primeiro sync da Application após criação | 3 s |
| Recriação dos recursos pelo ArgoCD | 61 s |
| Reconexão automática dos clientes | **não** — pool com ligações mortas (`E57P01`), reinício manual |
| Rolling update da Quinta (2 execuções) | **sem downtime** — sempre ≥1 réplica a servir |
| Distribuição das réplicas | 2 réplicas em nós diferentes (agent-0, agent-1) |
| **Perda de 1 réplica sob carga contínua** | **0 falhas em 300 pedidos — 100% de disponibilidade** |
| **Destruição das 2 réplicas sob carga contínua** | **19 falhas em 600 pedidos — 96,8% de disponibilidade**, janela de ~3,5–4 s, recuperação automática |
| Tempo de rolling update sem downtime | |
| Tempo de recuperação após falha do nó | |

A linha da reconexão é um resultado negativo e fica registada como tal. O
cluster recuperou em 6 s; os clientes não recuperaram sozinhos. Ver a lição
em `docs/04-deploy.md`, secção 4.6.

---

## Observabilidade

| Métrica | Valor |
|---|---|
| Alertas definidos | **7** (`monitoring/alerts.yaml`) |
| Stack instalada | kube-prometheus-stack, 13/08/2026 |
| Tempo de deteção (CrashLoop) | |
| Tempo de deteção (memória alta) | |

---

## Consumo em repouso — 13/08/2026

Namespace `quinta`, sem carga. Medido no Grafana.

| Pod | CPU (cores) | Memória |
|---|---|---|
| `quinta-web` (réplica 1) | 0,000438 | 37,2 MiB |
| `quinta-web` (réplica 2) | 0,000409 | 38,8 MiB |
| `postgres-0` | 0,00231 | 20,0 MiB |

| Agregado do namespace | Valor |
|---|---|
| CPU sobre requests | 1,05% |
| CPU sobre limits | 0,158% |
| Memória sobre requests | 18,9% |
| Memória sobre limits | 4,72% |

**Baseline de memória:** ~38 MiB por réplica Next.js em modo standalone,
~20 MiB para o PostgreSQL. As duas réplicas mais a base de dados cabem em menos
de 100 MiB.

**Right-sizing:** os requests de CPU do `quinta-web` estão cerca de **230×
acima** do consumo em repouso (0,100 pedidos contra 0,000438 usados). O
scheduler reserva o que está em `requests`, use-se ou não — requests
inflacionados reduzem a densidade de pods por nó e podem pôr pods em `Pending`
num cluster praticamente parado.

> Valores **em repouso**. Não servem para baixar requests: sob carga, o Next e
> o Postgres consomem muito mais. Decidir requests exige medir com carga real
> e olhar para percentis. Ver `docs/06-monitorizacao.md`, secção 6.6.

---

## GitOps

| Métrica | Valor |
|---|---|
| Tempo de sincronização após commit | |
| Tempo de self-heal após alteração manual | |
| Operações manuais de kubectl em produção | 0 |

---

## Bullets do currículo

Só os que já assentam em números medidos. Os restantes ficam por preencher até
a medição existir.

**Prontos:**

```
• Containerized a Next.js/Prisma application with a multi-stage Dockerfile,
  reducing image size from 3.4 GB to 282 MB (92% smaller, 12x) and building in
  ~54 s with layer caching.
• Migrated the application database from SQLite to PostgreSQL running in-cluster
  as a StatefulSet with persistent volumes, removing the single-replica
  constraint that made high availability impossible.
• Deployed PostgreSQL 16 on Kubernetes with a headless Service, PVC and
  Secret-based credentials; verified data persistence by destroying the pod —
  full recovery in 6 seconds with zero data loss.
• Built a 3-node Kubernetes cluster (k3s/k3d) with NGINX ingress, resource
  limits and liveness/readiness probes, provisioned from scratch by a single
  bootstrap script.
• Deployed the application across multiple nodes with 2 replicas and performed
  rolling updates with zero downtime, always keeping at least one replica
  serving traffic.
• Survived two unplanned power outages with no graceful shutdown: the cluster
  recovered autonomously in ~5 minutes both times, with zero manual
  intervention, remounting persistent volumes with no data loss.
• Implemented GitOps delivery with ArgoCD, reverting manual cluster changes in
  1-2 seconds — before the drifted state could materialize — and making every
  deployment an auditable Git commit.
• Load-tested failure scenarios from inside the cluster under continuous
  traffic: losing one of two replicas caused 0 failed requests out of 300
  (100% availability), while destroying all replicas simultaneously caused 19
  out of 600 (96.8%) with automatic recovery in under 4 seconds.
• Instrumented the cluster with Prometheus and Grafana, defining 7 alert rules
  scoped by namespace rather than resource name, and established resource
  baselines (~38 MiB per Next.js replica, ~20 MiB for PostgreSQL at rest).
```

**Por preencher (falta medir):**

```
• Packaged workloads as Helm charts with environment-specific values,
  standardizing deployments across dev and prod.
• ... cutting incident detection time to ___.
```

### O que continua por medir

| Métrica | Estado | Porque interessa |
|---|---|---|
| Tempo de deteção do alerta `PodCrashLooping` | pod de teste aplicado às 07:09:22 UTC de 13/08 | fecha o bullet da monitorização e o critério de sucesso do alerta |
| Reconstrução do cluster de raiz (`k3d cluster delete` + `bootstrap.sh`) | por fazer | é **o** teste do projeto: se falhar, a automação não está correta |
| Imagem e build da Briosa | por fazer | falta a segunda aplicação |
| Requests sob carga (right-sizing a sério) | por fazer | os valores em repouso não bastam para decidir |

> Nota para a entrevista: a redução de 92% da Quinta é multi-stage a sério.
> A da Briosa, quando existir, virá sobretudo de `.dockerignore` e limpeza de
> cache — não é a mesma história e não deve ser contada como se fosse.
