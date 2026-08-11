# 06 — Monitorização

## 6.1 O que foi instalado

`kube-prometheus-stack` — inclui Prometheus, Grafana, Alertmanager, node-exporter e kube-state-metrics num único chart.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword="<definida-fora-do-repositorio>" \
  --set prometheus.prometheusSpec.retention=7d \
  --set prometheus.prometheusSpec.resources.requests.memory=400Mi
```

> ⚠️ A password nunca fica no repositório. Passar por `--set` na linha de comandos ou por um Secret criado à parte.

---

## 6.2 Aceder

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3001:80
```

`http://localhost:3001` — utilizador `admin`.

---

## 6.3 Dashboards úteis (já incluídos)

- **Kubernetes / Compute Resources / Cluster** — visão geral de CPU e memória
- **Kubernetes / Compute Resources / Namespace (Pods)** — consumo por aplicação
- **Node Exporter / Nodes** — saúde dos nós

---

## 6.4 Alertas definidos

| Alerta | Condição | Porquê |
|---|---|---|
| PodCrashLooping | reinícios > 3 em 10 min | aplicação a falhar no arranque |
| PodNotReady | pod não-ready > 5 min | readiness a falhar |
| HighMemoryUsage | uso > 90% do limite | risco de OOMKill |
| IngressDown | ingress sem endpoints | serviço inacessível |

Regras em [`monitoring/alerts.yaml`](https://github.com/renatovdsilva/renato-alta-disponibilidade/blob/main/monitoring/alerts.yaml).

---

## 6.5 Teste do alerta

Provocar uma falha real e medir o tempo de deteção:

```bash
kubectl set image deployment/quinta-web web=quinta-calvario:nao-existe -n quinta
# observar o CrashLoopBackOff e cronometrar até o alerta disparar
kubectl rollout undo deployment/quinta-web -n quinta
```

**Registar o tempo em `docs/11-metricas.md`.** Esse número é o MTTR de deteção e vai para o currículo.

---

## Registo

| Data | Alerta testado | Tempo até disparar |
|---|---|---|
| | PodCrashLooping | |
