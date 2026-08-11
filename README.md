# Renato — Alta Disponibilidade

Plataforma Kubernetes auto-hospedada para correr as minhas aplicações em condições próximas de produção: containerização, orquestração multi-nó, ingress, observabilidade e entrega contínua por GitOps.

**Estado:** em construção
**Autor:** Renato Vieira da Silva — [github.com/renatovdsilva](https://github.com/renatovdsilva)

---

## Porquê

Depois de anos a administrar infraestrutura on-premise e um ambiente Kubernetes híbrido no Grupo Christus, este projeto é a minha plataforma pessoal para manter e aprofundar a prática em ferramentas cloud-native — e para servir de base às aplicações que desenvolvo.

O objetivo não é "brincar com Kubernetes". É reproduzir, à escala de uma máquina, as decisões que se tomam num ambiente real: alta disponibilidade, limites de recursos, health checks, segregação por namespace, monitorização com alertas e deploys auditáveis.

---

## Arquitetura

```
                    ┌──────────────────────────────┐
   browser ────────▶│   Ingress NGINX (LoadBalancer)│
                    └───────────────┬──────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              ▼                     ▼                     ▼
      ┌──────────────┐     ┌──────────────┐      ┌──────────────┐
      │ ns: quinta   │     │ ns: briosa   │      │ ns: monitoring│
      │ Next.js app  │     │ PHP app      │      │ Prometheus    │
      │ 2 réplicas   │     │ 2 réplicas   │      │ Grafana       │
      └──────────────┘     └──────────────┘      └──────────────┘
              ▲                     ▲
              └──────────┬──────────┘
                         │
                 ┌───────────────┐
                 │ ns: argocd    │  ◀── sincroniza a partir deste repositório
                 └───────────────┘

   Cluster k3s (k3d): 1 control plane + 2 workers
   Host: Windows 11 + WSL2 (Ubuntu 22.04) + Docker
```

---

## Estrutura do repositório

| Pasta | Conteúdo |
|---|---|
| `docs/` | Documentação de todos os processos — instalação, decisões, operação, troubleshooting |
| `apps/` | Dockerfiles e notas de build de cada aplicação |
| `k8s/base/` | Manifests base (Deployment, Service, Ingress, Namespace) |
| `k8s/overlays/` | Variações por ambiente (dev e prod) |
| `charts/` | Helm charts das aplicações |
| `argocd/` | Definições de Application do ArgoCD |
| `monitoring/` | Configuração de Prometheus, Grafana e regras de alerta |
| `scripts/` | Automação — bootstrap do cluster, build e import de imagens |

---

## Como reproduzir

```bash
git clone https://github.com/renatovdsilva/renato-alta-disponibilidade.git
cd renato-alta-disponibilidade
./scripts/bootstrap.sh
```

O detalhe completo está em [`docs/01-instalacao.md`](docs/01-instalacao.md).

---

## Stack

Kubernetes (k3s/k3d) · Docker · Helm · Ingress NGINX · ArgoCD · Prometheus · Grafana · Linux (Ubuntu/WSL2) · Bash · Git

---

## Documentação

O processo está documentado do zero — desde a verificação da BIOS até ao deploy com GitOps.

| # | Documento | O que cobre |
|---|---|---|
| 00 | [Ponto de partida](docs/00-ponto-de-partida.md) | Estado inicial da máquina, objetivos e critérios de sucesso |
| 01a | [Instalação do WSL2](docs/01-instalacao-wsl2.md) | Virtualização, WSL2, Ubuntu, .wslconfig, Docker Desktop |
| 01b | [Instalação das ferramentas](docs/01-instalacao.md) | kubectl, k3d, Helm |
| 02 | [Criação do cluster](docs/02-cluster.md) | k3d, 3 nós, Ingress NGINX |
| 03 | [Containerização](docs/03-containerizacao.md) | Dockerfiles multi-stage, import de imagens |
| 04 | [Deploy](docs/04-deploy.md) | Deployments, Services, Ingress, testes de resiliência |
| 05 | [Helm](docs/05-helm.md) | Charts, values por ambiente, rollback |
| 06 | [Monitorização](docs/06-monitorizacao.md) | Prometheus, Grafana, alertas |
| 07 | [GitOps](docs/07-gitops.md) | ArgoCD, sincronização automática, self-heal |
| 08 | [Operação](docs/08-operacao.md) | Rotina diária, publicação de versões, backup |
| 09 | [Troubleshooting](docs/09-troubleshooting.md) | Problemas encontrados e como foram resolvidos |
| 10 | [Decisões de arquitetura](docs/10-decisoes.md) | Escolhas, alternativas e custos |
| 11 | [Métricas](docs/11-metricas.md) | Números medidos, base dos bullets do currículo |
