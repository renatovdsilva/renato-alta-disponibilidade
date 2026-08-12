# 06 — Monitorização

## 6.1 O que foi instalado

`kube-prometheus-stack` — inclui Prometheus, Grafana, Alertmanager, node-exporter e kube-state-metrics num único chart.

```bash
cd ~/Documents/renato-alta-disponibilidade

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

GRAFANA_PASS="$(openssl rand -base64 24 | tr -d '/+=')"
echo "Password do Grafana: $GRAFANA_PASS"

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f monitoring/kube-prometheus-stack.values.yaml \
  --set grafana.adminPassword="$GRAFANA_PASS" \
  --wait --timeout 10m

kubectl -n monitoring get pods
```

Os parâmetros estão em
[`monitoring/kube-prometheus-stack.values.yaml`](https://github.com/renatovdsilva/renato-alta-disponibilidade/blob/main/monitoring/kube-prometheus-stack.values.yaml),
não espalhados por `--set`. A password é a única exceção: vai pela linha de
comandos e nunca fica em ficheiro (D7).

### O que foi desligado, e porquê

Num cluster k3s três componentes do chart não têm como funcionar:

| Componente | Razão |
|---|---|
| `kubeScheduler` | o k3s corre-o dentro do processo único do servidor, sem expor a porta 10259 |
| `kubeControllerManager` | idem, sem a porta 10257 |
| `kubeEtcd` | o k3s usa SQLite por omissão; não há etcd nem a porta 2381 |
| `kubeProxy` | embutido no agente, sem endpoint de métricas próprio |

Deixá-los ligados não parte nada — produz alvos permanentemente `down` no
Prometheus e faz disparar o `TargetDown` do próprio chart. O custo é pior do
que parece: **habitua a ignorar alertas**, e um alerta que se aprende a ignorar
já não é um alerta.

O `kubelet` e o cAdvisor ficam ligados, e são eles que dão CPU e memória por
container.

### Armazenamento persistente

O Prometheus e o Grafana ficam com PVC em vez de `emptyDir`. Depois da queda de
energia de 12/08 (doc 08, secção 8.5), guardar métricas em memória volátil
deixou de fazer sentido: o histórico é precisamente o que se quer consultar
**depois** de um incidente, e um `emptyDir` perde-o exatamente quando é
preciso.

---

## 6.2 Aceder

As portas 8080 e 8081 já estão ocupadas por outros port-forwards (Ingress e
ArgoCD). Estas três estão livres:

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3001:80 &
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093 &
```

| Serviço | Endereço | Utilizador |
|---|---|---|
| Grafana | `http://localhost:3001` | `admin` |
| Prometheus | `http://localhost:9090` | — |
| Alertmanager | `http://localhost:9093` | — |

Recuperar a password do Grafana a qualquer momento:

```bash
kubectl -n monitoring get secret monitoring-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Confirmar que os alvos estão todos verdes em
`http://localhost:9090/targets` — depois de desligar os quatro componentes
acima, não deve haver nenhum `down`.

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
| DeploymentSemReplicas | zero réplicas disponíveis | serviço em baixo |
| DeploymentDegradado | disponíveis < desejadas, > 10 min | a correr sem redundância — o serviço está de pé mas deixou de ser HA |
| BaseDeDadosIndisponivel | StatefulSet sem réplicas prontas | Postgres ou MySQL em baixo |
| VolumeQuaseCheio | PVC com menos de 15% livre | o `local-path` não cresce sozinho |

**Nenhuma regra refere nomes de Deployment.** Filtram por namespace e por
labels, de propósito: o nome da Quinta já mudou uma vez (`quinta-web` →
`quinta-quinta`) e vai mudar outra. Um alerta preso a um nome deixa de avaliar
o que quer que seja sem dar erro — falha silenciosa, que é a pior espécie.

O namespace `briosa` já está nas regras apesar de estar vazio. Sem métricas, as
regras não avaliam nada; quando a Briosa entrar, ficam a cobri-la sem
alterações.

**`IngressDown` não foi implementado.** As métricas do Ingress NGINX exigem
`controller.metrics.enabled=true` e um ServiceMonitor, e o controller foi
instalado sem isso. O comando para reinstalar com métricas está em comentário
no fim de `monitoring/alerts.yaml`. Entretanto, `DeploymentSemReplicas` cobre
o caso prático: sem pods, o Ingress não tem para onde encaminhar.

Regras em [`monitoring/alerts.yaml`](https://github.com/renatovdsilva/renato-alta-disponibilidade/blob/main/monitoring/alerts.yaml).

---

## 6.5 Teste do alerta

### O problema: o ArgoCD não deixa

O procedimento óbvio — estragar a Quinta de propósito — **não funciona mais**.
A Quinta é gerida pelo ArgoCD com `selfHeal: true`, que repõe a versão do Git
em 1-2 segundos. O pod nunca chega a `CrashLoopBackOff` e o alerta nunca
dispara. Não é o alerta que está mal: é o teste que deixou de ser válido.

### Método recomendado: um pod descartável

Um Deployment que não pertence a nenhuma Application, no namespace `quinta`
para ser apanhado pelas regras (que filtram por namespace, não por nome):

```bash
# t=0 — anotar a hora
date -u

kubectl apply -f monitoring/crashloop-test.yaml
kubectl get pods -n quinta -w        # ver os reinícios a acumular
```

Acompanhar o alerta a mudar de estado em `http://localhost:9090/alerts`:

| Estado | Significa |
|---|---|
| *inactive* | a condição não se verifica |
| **pending** | a condição verifica-se, mas ainda não há `for: 2m` |
| **firing** | disparou — chegou ao Alertmanager |

```bash
# consultar por linha de comandos, sem UI
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | {nome:.labels.alertname, estado:.state, desde:.activeAt}'
```

Limpar no fim — não deixa rasto nenhum:

```bash
kubectl delete -f monitoring/crashloop-test.yaml
```

**O que cronometrar.** O tempo total de deteção tem duas parcelas, e vale a
pena registá-las separadas:

1. **até `pending`** — tempo para acumular mais de 3 reinícios em 10 minutos,
   condicionado pelo backoff do kubelet (10 s, 20 s, 40 s...) e pelo intervalo
   de scraping (30 s por omissão)
2. **de `pending` a `firing`** — os `for: 2m` da regra, fixos

O `for` existe para não disparar com um reinício isolado. É uma escolha
deliberada entre ruído e rapidez: baixá-lo dá um número melhor no currículo e
um alerta pior na prática.

### Variante com a aplicação real

Mais convincente, porque usa a aplicação verdadeira. Exige desligar
temporariamente o self-heal:

```bash
# 1) desligar a sincronização automática
kubectl -n argocd patch application quinta --type merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'

# 2) provocar a falha (imagem que não existe em nó nenhum)
kubectl set image deployment/quinta-quinta web=quinta-calvario:nao-existe -n quinta
date -u

# 3) cronometrar até firing em http://localhost:9090/alerts
#    nota: com uma imagem inexistente o estado é ImagePullBackOff, não
#    CrashLoopBackOff — quem dispara é o PodNotReady, não o PodCrashLooping

# 4) repor: basta voltar a ligar a automação, o ArgoCD corrige sozinho
kubectl -n argocd patch application quinta --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'

kubectl -n argocd get application quinta
kubectl get pods -n quinta
```

O passo 4 é o que torna isto seguro: não é preciso `rollout undo` nem lembrar
qual era a tag anterior. O estado correto está no Git, e ligar a automação
repõe-no. É a mesma propriedade que faz do GitOps uma rede de segurança e não
só uma automação.

> O nome `quinta-quinta` é o gerado pelo chart antes de o `fullnameOverride`
> chegar ao Git. Confirmar sempre com `kubectl get deploy -n quinta` antes de
> colar o comando.

**Registar os tempos em `docs/11-metricas.md`.**

---

## Registo

| Data | Alerta testado | Tempo até disparar |
|---|---|---|
| | PodCrashLooping | |
