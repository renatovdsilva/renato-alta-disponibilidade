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
- [ ] As duas aplicações respondem no browser através do Ingress
- [ ] Matar um pod não interrompe o serviço, e isso está medido
- [ ] O Grafana mostra métricas dos pods e dos nós
- [ ] Um alerta dispara quando se provoca uma falha, com tempo registado
- [ ] Um commit no Git provoca deploy automático sem intervenção
- [ ] Alterar o cluster à mão é revertido pelo ArgoCD
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
| 10/08/2026 | 1 | | WSL2 + Ubuntu 22.04, Docker Desktop 4.86.0 integrado, kubectl v1.36.3, k3d v5.9.0 e Helm v3.21.3 instalados. Dois erros de integração do Docker/WSL resolvidos e documentados em `01-instalacao-wsl2.md`. | — (sessão fechada) |
| 10–11/08/2026 | 2 | | Cluster `alta-disponibilidade` criado (1 control plane + 2 workers, k3s v1.35.5+k3s1), 3 nós `Ready` em ~75 s. Traefik desativado na criação. Ingress NGINX instalado por Helm em 11/08 — controller `1/1 Running` em ~76 s, service `LoadBalancer` ativo. | — (sessão fechada) |
| 11/08/2026 | 3 | | Node 20 instalado no Ubuntu (o `npm` era o do Windows). Quinta do Calvário executada pela primeira vez: `next.config.ts` → `.mjs`, variáveis do NextAuth, Prisma 5.22, seed e login funcionais. Migração SQLite → PostgreSQL (D9): Postgres 16.14 no cluster, `postgres-0` `1/1 Running`, PVC 2 Gi `Bound`, schema por `db push`, seed e login contra o cluster. Teste de persistência: pod destruído, `Ready` em 6 s, dados intactos. Imagem da Quinta de 3,4 GB para 282 MB (−92%). Briosa: estrutura real levantada, Dockerfile corrigido e manifests do MySQL escritos. | Migrações versionadas do Prisma (`shadowDatabaseUrl`); build e deploy da Briosa; aplicações ainda não estão a correr no cluster |
| | 4 | | | |
