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

Desde 14/08/2026 o acesso é por **Ingress**, não por port-forward — os
port-forwards morriam a cada queda de energia e tinham de ser repostos à mão
(ver `docs/08-operacao.md`, secção 8.6).

```bash
kubectl apply -f k8s/platform/ingress-plataforma.yaml
```

| Serviço | Endereço | Utilizador |
|---|---|---|
| Grafana | `http://grafana.localhost` | `admin` |
| Prometheus | `http://prometheus.localhost` | — |
| Alertmanager | *(sem Ingress — port-forward quando for preciso)* | — |

O Grafana precisa de saber em que URL está a ser servido, senão constrói
ligações absolutas para `http://localhost:3000`:

```yaml
grafana:
  grafana.ini:
    server:
      domain: grafana.localhost
      root_url: "http://grafana.localhost"
```

Já está no ficheiro de valores. Aplicar com `helm upgrade`.

Para o Alertmanager, ou em caso de necessidade pontual:

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093
```

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

### A monitorização pagou-se antes do teste acabar

O primeiro alerta a disparar não foi o do pod de teste. Foi um problema real
que já existia havia 24 horas: o `argocd-applicationset-controller` em
CrashLoopBackOff, com **208 reinícios acumulados**, desde a instalação do
ArgoCD no dia anterior.

Ninguém tinha dado por isso — e não por distração. O ArgoCD funcionava:
Applications sincronizadas, self-heal a responder em 1-2 segundos, tudo
`Healthy`. O componente avariado não é usado por nada aqui, portanto a avaria
não tinha sintoma visível.

**É exatamente para isto que serve monitorizar.** Sem métricas, o problema
continuaria escondido até ao dia em que fizesse falta um ApplicationSet — e
nessa altura o diagnóstico seria feito à pressa, com alguém a precisar da
funcionalidade.

Diagnóstico completo e causa raiz (um CRD que falhou em silêncio por exceder o
limite de 256 KB das anotações do etcd) em `docs/09-troubleshooting.md`.

---

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

**Não esperar deteção imediata.** Há dois alertas de CrashLoop no cluster, com
tempos muito diferentes:

| Regra | Origem | Expressão | `for` | Ordem de grandeza |
|---|---|---|---|---|
| `PodCrashLooping` | nossa (`monitoring/alerts.yaml`) | `increase(...[10m]) > 3` | 2m | poucos minutos |
| `KubePodCrashLooping` | do chart | `max_over_time(...[5m])` | **15m** | **15 a 20 min** |

Pod de teste aplicado às **07:09:22 UTC** em 13/08/2026.

**Janela da expressão e `for` são coisas distintas**, e é onde se confundem
expectativas:

- a **janela** (`[5m]`, `[10m]`) é o intervalo de tempo que a consulta olha
  para trás em cada avaliação — define *o que* conta como condição verdadeira
- o **`for`** é quanto tempo essa condição tem de se manter verdadeira, em
  avaliações consecutivas, antes de o alerta passar de `pending` a `firing`

Somam-se: com `[5m]` e `for: 15m`, entre o primeiro reinício e o `firing` podem
passar 20 minutos. Não é lentidão nem avaria — é a rede de segurança contra
alertas por um reinício isolado.

**O que cronometrar,** em duas parcelas separadas:

1. **até `pending`** — acumular reinícios suficientes, condicionado pelo
   backoff do kubelet (10 s, 20 s, 40 s...) e pelo scraping (30 s)
2. **de `pending` a `firing`** — o `for` da regra, fixo

Baixar o `for` dá um número melhor no currículo e um alerta pior na prática. A
escolha deve ser explicada, não otimizada.

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

| Data | Ação | Resultado |
|---|---|---|
| 13/08/2026 | `kube-prometheus-stack` instalado | **ok**, sem erros, namespace `monitoring`, com o ficheiro de valores do repositório |
| 13/08/2026 | acesso | Grafana em `localhost:3001`, Prometheus em `localhost:9090` |
| 13/08/2026 | primeiras métricas | dashboard *Compute Resources / Namespace (Pods)* a mostrar `quinta` — ver 6.6 |

| Data | Alerta testado | Tempo até disparar |
|---|---|---|
| | PodCrashLooping | |

Password do `admin` do Grafana, se for preciso outra vez:

```bash
kubectl -n monitoring get secret -l app.kubernetes.io/component=admin-secret \
  -o jsonpath='{.items[0].data.admin-password}' | base64 -d; echo
```

---

## 6.6 Primeira leitura real — 13/08/2026

Namespace `quinta`, em repouso, sem carga nenhuma.

### Agregados do namespace

| Métrica | Valor |
|---|---|
| CPU utilizado / requests | **1,05%** |
| CPU utilizado / limits | 0,158% |
| Memória utilizada / requests | **18,9%** |
| Memória utilizada / limits | 4,72% |

### Por pod

| Pod | CPU (cores) | Memória | Request CPU | % do request |
|---|---|---|---|---|
| `quinta-web-…-jzs6p` | 0,000438 | 37,2 MiB | 0,100 | 0,438% |
| `quinta-web-…-2wjvf` | 0,000409 | 38,8 MiB | 0,100 | 0,409% |
| `postgres-0` | 0,00231 | 20,0 MiB | 0,100 | 2,31% |

### As quatro caixas do topo não medem a mesma coisa

O dashboard mostra utilização sobre `requests` **e** sobre `limits`, e a
diferença entre as duas é o que explica quase tudo o resto:

- **sobre requests** — quanto se usa daquilo que foi *reservado*. O scheduler
  aparta essa capacidade no nó, use-se ou não. É o número que diz se o cluster
  está a ser desperdiçado.
- **sobre limits** — quanto falta para bater no teto. É o número que avisa de
  *throttling* de CPU e de OOMKill.

Um pod pode estar nos 5% do limite e nos 90% do request: folga para crescer,
mas a reservar quase tudo o que pediu. Ou o contrário. Olhar só para uma das
duas dá sempre metade da história.

### Right-sizing: os requests estão ~230× acima do uso

O `quinta-web` pede 0,100 cores e consome 0,000438 — cerca de **230 vezes
menos** do que reserva.

Porque é que isso importa, mesmo com CPU de sobra: o scheduler decide onde cabe
um pod pela soma dos `requests` do nó, **não** pelo consumo real. Requests
inflacionados fazem o nó parecer cheio enquanto está praticamente parado, e o
resultado é menos pods por nó, ou pods em `Pending` num cluster ocioso.

Num laboratório com 12 CPUs isto não custa nada. Num cluster gerido, é
diretamente fatura ao fim do mês.

> **O que estes números não autorizam.** São valores **em repouso, sem uma
> única visita à aplicação**. Baixar os requests com base neles seria trocar um
> erro por outro: com carga, um arranque de Next.js ou uma query pesada de
> Postgres consomem muito mais, e um request demasiado baixo faz o scheduler
> empilhar pods que depois competem por CPU.
>
> Para decidir a sério é preciso medir sob carga — um teste com `hey` ou `k6`,
> a olhar para os percentis, não para a média. Fica como trabalho futuro.

### Baseline de memória

Números úteis para justificar o dimensionamento do cluster:

| Componente | Memória em repouso |
|---|---|
| Réplica Next.js (standalone) | **~38 MiB** |
| PostgreSQL 16 | **~20 MiB** |

Duas réplicas da Quinta mais a base de dados cabem em menos de 100 MiB. O
`output: 'standalone'` do Next não corta só o tamanho da imagem — corta também
o que fica residente em memória.
