# 00 — Ponto de partida

Documento inicial do projeto. Regista o estado da máquina antes de qualquer instalação, o que se pretende alcançar e como se sabe que está feito.

---

## Contexto

Administrei infraestrutura durante mais de doze anos, incluindo um ambiente Kubernetes híbrido no Grupo Christus com nós bare-metal e cargas no Google Cloud Platform. Desde a mudança para Portugal em 2024 a minha função tem sido de administração de sistemas generalista, sem contacto diário com orquestração de contentores.

Este projeto existe para recuperar e aprofundar essa prática, e para servir de plataforma às aplicações que desenvolvo.

---

## Objetivos

1. Cluster Kubernetes multi-nó a correr localmente, com alta disponibilidade demonstrável.
2. As minhas aplicações containerizadas e a correr nesse cluster.
3. Observabilidade com métricas e alertas que disparam a sério.
4. Entrega contínua por GitOps, sem `kubectl apply` manual.
5. Todo o processo documentado, reprodutível do zero por um comando.
6. Preparação prática para o exame CKA.

---

## Não-objetivos

- Não é para substituir um cluster de produção.
- Não vai suportar tráfego real de utilizadores.
- Não vai ter alta disponibilidade do control plane (um único servidor). Isso é limitação assumida, não esquecimento — ver `docs/10-decisoes.md`.

---

## Estado inicial da máquina

Preencher antes de começar:

Recolhido em 10/08/2026:

| Item | Valor |
|---|---|
| Sistema operativo | Windows 11 Pro |
| Versão (`winver`) | 25H2 — build 26200.8875 |
| CPU | AMD Ryzen 9 7900X |
| Núcleos / threads | 12 / 24 |
| RAM total | 32 GB (33 445 580 800 bytes) |
| Disco C: | 439 GB usados / **491 GB livres** |
| Virtualização na BIOS | *a confirmar no Gestor de Tarefas* |
| WSL já instalado | **não** — instalação limpa |
| Docker já instalado | *a confirmar* |

**Avaliação:** a máquina está muito acima do necessário. Com 24 threads e 32 GB de RAM é possível correr o cluster, a stack de monitorização completa e o ArgoCD em simultâneo sem qualquer aperto — e ainda sobra folga para aumentar o número de nós se quiser testar cenários de scheduling.

Comandos para recolher estes dados, no PowerShell:

```powershell
winver
Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors
Get-CimInstance Win32_ComputerSystem | Select-Object TotalPhysicalMemory
Get-PSDrive C | Select-Object Used, Free
systeminfo | Select-String "Hyper-V"
wsl -l -v
```

---

## Critérios de sucesso

O projeto está concluído quando todas estas afirmações forem verdadeiras:

- [x] `kubectl get nodes` mostra três nós em `Ready` *(confirmado em 11/08/2026 — ver `02-cluster.md`)*
- [x] As aplicações respondem no browser através do Ingress *(27/08/2026 — Quinta, RenatoTrack e FitnessPHIVE. A Briosa continua por construir)*
- [x] Matar um pod não interrompe o serviço, e isso está medido *(13/08/2026 — perda de 1 réplica: **0 falhas em 300 pedidos**; destruição total: 19/600, 96,8%)*
- [x] O Grafana mostra métricas dos pods e dos nós *(13/08/2026 — ver `06-monitorizacao.md`, 6.6)*
- [ ] Um alerta dispara quando se provoca uma falha, com tempo registado
- [x] Um commit no Git provoca deploy automático sem intervenção *(13/08/2026 — o push trocou `quinta-quinta` por `quinta-web` sem qualquer `kubectl`)*
- [x] Alterar o cluster à mão é revertido pelo ArgoCD *(12/08/2026 — reposto em 1–2 s)*
- [ ] `k3d cluster delete` seguido de `./scripts/bootstrap.sh` reconstrói tudo
- [ ] O ficheiro `docs/11-metricas.md` está preenchido com números medidos
- [ ] Um estranho consegue reproduzir o ambiente só com esta documentação

---

## Plano por sessões

| Sessão | Documentos | Entrega |
|---|---|---|
| 1 | 00, 01a, 01b | WSL2, Docker e ferramentas instalados |
| 2 | 02 | Cluster de 3 nós com Ingress |
| 3 | 03, 04 | Aplicações containerizadas e acessíveis |
| 4 | 05 | Helm charts com values por ambiente |
| 5 | 06 | Prometheus, Grafana e alertas testados |
| 6 | 07 | ArgoCD a sincronizar a partir do Git |
| 7 | 08–11 | Documentação fechada e métricas preenchidas |

---

## Registo de sessões

| Data | Sessão | Tempo | O que ficou feito | O que ficou por fazer |
|---|---|---|---|---|
| 10/08/2026 | 1 | | WSL2 + Ubuntu 22.04, Docker Desktop 4.86.0 integrado, kubectl v1.36.3, k3d v5.9.0 e Helm v3.21.3 instalados. Dois erros de integração do Docker/WSL resolvidos e documentados em `01a-instalacao-wsl2.md`. | — (sessão fechada) |
| 10–11/08/2026 | 2 | | Cluster `alta-disponibilidade` criado (1 control plane + 2 workers, k3s v1.35.5+k3s1), 3 nós `Ready` em ~75 s. Traefik desativado na criação. Ingress NGINX instalado por Helm em 11/08 — controller `1/1 Running` em ~76 s, service `LoadBalancer` ativo. | — (sessão fechada) |
| 11/08/2026 | 3 | | Node 20 instalado no Ubuntu (o `npm` era o do Windows). Quinta do Calvário executada pela primeira vez: `next.config.ts` → `.mjs`, variáveis do NextAuth, Prisma 5.22, seed e login funcionais. Migração SQLite → PostgreSQL (D9): Postgres 16.14 no cluster, `postgres-0` `1/1 Running`, PVC 2 Gi `Bound`, schema por `db push`, seed e login contra o cluster. Teste de persistência: pod destruído, `Ready` em 6 s, dados intactos. Imagem da Quinta de 3,4 GB para 282 MB (−92%). Briosa: estrutura real levantada, Dockerfile corrigido e manifests do MySQL escritos. | Migrações versionadas do Prisma (`shadowDatabaseUrl`); build e deploy da Briosa; aplicações ainda não estão a correr no cluster |
| 11/08/2026 | 3 (cont.) | | Deploy da Quinta no cluster: imagem importada para os 3 nós em 6 s, `quinta-web` com 2 réplicas em nós diferentes, Service e Ingress aplicados, login funcional. Rolling update demonstrado 2× sem downtime. Acesso externo por túnel cloudflared, validado por outra pessoa noutra rede. Repositório publicado e GitHub Pages ativas. | Briosa por construir; migrações versionadas do Prisma |
| 12/08/2026 | 6 | | ArgoCD v3.5.0 instalado. Quinta migrada de `kubectl apply` para GitOps: recursos antigos apagados (dados intactos), Application `Healthy`/`Synced`, primeiro sync em 3 s e recursos recriados em 61 s. Self-heal validado — `scale` manual revertido em 1–2 s. **Queda de energia real às 07:41**: cluster recuperou sozinho em ~5 min, sem intervenção e sem perda de dados. | Chart em produção ainda é a versão antiga do Git (nomes `quinta-quinta`); falta commit e push |
| 13/08/2026 | 5 | | `kube-prometheus-stack` instalado sem erros, com valores versionados e PVC para Prometheus e Grafana. Sete regras de alerta, filtradas por namespace e não por nome. Primeira leitura real do consumo: ~38 MiB por réplica Next.js, ~20 MiB no Postgres, CPU a 1% dos requests. Ciclo GitOps completo validado: o push corrigiu os nomes dos recursos sem qualquer `kubectl`. | Cronometrar o alerta `PodCrashLooping`; medir requests sob carga; Briosa |
| 27/08/2026 | 6 (cont.) | | **Três aplicações geridas por GitOps**, todas `Synced` e `Healthy`: `quinta` (Helm), `renatotrack` (manifests, sync à primeira) e `fitness` (Kustomize, cinco correções antes do primeiro sync). O cluster deixou de ter estado que não esteja versionado. | Cronometrar o alerta; reconstrução pelo bootstrap; Briosa |
| | 4 | | *(Helm — o chart já está em uso pelo ArgoCD; falta fechar o doc 05)* | |
