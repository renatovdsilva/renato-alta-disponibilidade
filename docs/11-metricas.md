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
| **Queda de energia real** (12/08/2026, sem encerramento ordenado) | **~5 min** até todos os pods `Running`, **zero intervenção manual**, PVC remontado com o mesmo id e dados intactos |
| Estabilidade do cluster antes da queda | 38 h contínuas, 3 nós `Ready`, sem falhas |
| Self-heal do ArgoCD (`scale` manual → reposto) | **1–2 s** — as réplicas extra nunca chegaram a materializar-se |
| Primeiro sync da Application após criação | 3 s |
| Recriação dos recursos pelo ArgoCD | 61 s |
| Reconexão automática dos clientes | **não** — pool com ligações mortas (`E57P01`), reinício manual |
| Rolling update da Quinta (2 execuções) | **sem downtime** — sempre ≥1 réplica a servir |
| Distribuição das réplicas | 2 réplicas em nós diferentes (agent-0, agent-1) |
| Pedidos falhados ao matar um pod da aplicação | *(por medir — falta o teste com `curl` em ciclo)* |
| Tempo de rolling update sem downtime | |
| Tempo de recuperação após falha do nó | |

A linha da reconexão é um resultado negativo e fica registada como tal. O
cluster recuperou em 6 s; os clientes não recuperaram sozinhos. Ver a lição
em `docs/04-deploy.md`, secção 4.6.

---

## Observabilidade

| Métrica | Valor |
|---|---|
| Alertas definidos | |
| Tempo de deteção (CrashLoop) | |
| Tempo de deteção (memória alta) | |

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
• Survived an unplanned power outage with no graceful shutdown: the cluster
  recovered autonomously in ~5 minutes with zero manual intervention, remounting
  persistent volumes with no data loss.
• Implemented GitOps delivery with ArgoCD, reverting manual cluster changes in
  1-2 seconds — before the drifted state could materialize — and making every
  deployment an auditable Git commit.
```

**Por preencher (falta medir):**

```
• ... running self-developed applications with ___ requests lost during pod
  replacement.
• Packaged workloads as Helm charts with environment-specific values,
  standardizing deployments across dev and prod.
• Implemented GitOps delivery with ArgoCD, making every deployment an auditable
  Git commit and eliminating manual kubectl operations in production.
• Instrumented the cluster with Prometheus and Grafana, defining ___ alerts and
  cutting incident detection time to ___.
```

> Nota para a entrevista: a redução de 92% da Quinta é multi-stage a sério.
> A da Briosa, quando existir, virá sobretudo de `.dockerignore` e limpeza de
> cache — não é a mesma história e não deve ser contada como se fosse.
