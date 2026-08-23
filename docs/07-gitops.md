# 07 — GitOps com ArgoCD

## 7.1 O que muda

Sem GitOps, o estado do cluster vive na cabeça de quem correu o último `kubectl apply`.
Com GitOps, o estado desejado está no Git e o ArgoCD encarrega-se de o fazer coincidir com a realidade.

| Antes | Depois |
|---|---|
| `kubectl apply` manual | commit no Git |
| sem histórico de quem alterou | histórico completo no Git |
| drift silencioso | ArgoCD deteta e corrige |
| rollback = lembrar-se do estado anterior | rollback = `git revert` |

---

## 7.2 Instalação

```bash
kubectl create namespace argocd
kubectl apply --server-side -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd get pods
```

> **`--server-side` não é opcional.** Sem ele, o CRD dos ApplicationSets falha
> em silêncio no meio do output: o `kubectl apply` clássico guarda uma cópia
> integral do manifesto na anotação `last-applied-configuration`, e esse CRD é
> grande ao ponto de ultrapassar o limite de 256 KB do etcd.
>
> O resultado é traiçoeiro — o ArgoCD instala e funciona, mas o
> `argocd-applicationset-controller` fica em CrashLoopBackOff permanente,
> à procura de um tipo de recurso que não existe. Aconteceu aqui, e só foi
> descoberto 24 horas e 208 reinícios depois, pela monitorização. Ver
> `docs/09-troubleshooting.md`.
>
> Se a instalação já foi feita sem `--server-side`:
> ```bash
> kubectl apply --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/crds/applicationset-crd.yaml
> kubectl -n argocd rollout restart deploy/argocd-applicationset-controller
> ```
>
> Confirmar que ficou tudo de pé, e não apenas o `argocd-server`:
> ```bash
> kubectl -n argocd get pods
> kubectl get crd | grep argoproj
> ```

Password inicial do `admin`:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

Aceder à UI — desde 14/08/2026 por Ingress, em `http://argocd.localhost`:

```bash
# uma vez: pôr o servidor em modo inseguro, para o NGINX falar HTTP com ele
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}'
kubectl -n argocd rollout restart deploy/argocd-server

kubectl apply -f k8s/platform/ingress-plataforma.yaml
```

Sem o modo inseguro, o `argocd-server` redireciona HTTP para HTTPS e o
resultado atrás do Ingress é um ciclo de redirecionamentos. A alternativa era
a anotação `backend-protocol: "HTTPS"` — a escolha e a razão estão comentadas
no próprio manifesto.

Em caso de necessidade pontual, o port-forward continua a funcionar:

```bash
kubectl port-forward svc/argocd-server -n argocd 8081:443   # https://localhost:8081
```

Depois de entrar, mudar a password e apagar o secret inicial:

```bash
kubectl -n argocd delete secret argocd-initial-admin-secret
```

### Alternativa: expor por Ingress

Só vale a pena se o port-forward incomodar. O `argocd-server` fala HTTPS, e o
Ingress NGINX por omissão fala HTTP com o backend — sem uma das duas
configurações abaixo, o resultado é um ciclo de redirecionamentos:

- anotação `nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"` no Ingress, ou
- pôr o servidor em modo inseguro (`server.insecure: "true"` no ConfigMap
  `argocd-cmd-params-cm`) e deixar o TLS para o Ingress.

Neste laboratório ficou-se pelo port-forward: menos peças, e o ArgoCD não
precisa de estar acessível a partir do exterior.

---

## 7.3 Pré-requisitos que o ArgoCD **não** resolve

Isto é a parte que costuma correr mal na primeira tentativa. O ArgoCD aplica
manifests a partir do Git — não constrói imagens, não cria segredos, não
inventa o que não está lá.

| Pré-requisito | Porque não vem do Git | Se faltar |
|---|---|---|
| Secret `quinta-db` no namespace `quinta` | decisão D7: nenhum segredo no repositório | pods em `CreateContainerConfigError` |
| PostgreSQL a correr (`k8s/base/13` e `14`) | o chart cobre só a aplicação | pods arrancam mas falham a readiness |
| Imagem `quinta-calvario:1.0.0` nos nós | não está em registo nenhum | `ImagePullBackOff` |

**A imagem é o ponto mais importante.** Foi construída localmente e importada
com `k3d image import` — não existe num registo de onde o cluster a possa
puxar. Por isso o chart usa `imagePullPolicy: IfNotPresent`: o kubelet usa a
cópia que já está no nó e não tenta ir buscar nada.

```bash
# confirmar que a imagem está nos nós antes de sincronizar
k3d image import quinta-calvario:1.0.0 -c alta-disponibilidade
```

Consequência para o fluxo GitOps: **um commit que mude a tag da imagem não
chega**. É preciso construir e importar a nova tag primeiro, senão o ArgoCD
sincroniza para uma imagem que nenhum nó tem. Enquanto não houver registo, o
GitOps aqui é completo para configuração e parcial para imagens — e isso deve
ser dito assim, não escondido.

> `imagePullPolicy: Never` seria ainda mais explícito, ao proibir qualquer
> tentativa de download. Ficou `IfNotPresent` para o chart continuar a
> funcionar sem alterações no dia em que houver registo.

---

## 7.4 O conflito dos dois donos

A Quinta já está a correr, aplicada com `kubectl apply -f k8s/base/`. Se o
ArgoCD passar a geri-la pelo chart, os mesmos objetos passam a ter duas fontes
de verdade.

O chart foi alinhado para produzir **exatamente os mesmos nomes** dos manifests
base (`fullnameOverride: quinta-web`) — sem isso, uma release chamada `quinta`
geraria `quinta-quinta` e ficariam dois conjuntos de objetos a servir a mesma
aplicação, com dois Ingress a disputar o mesmo host.

Mas os nomes iguais não bastam. Há uma diferença que impede a adoção direta:

| | `k8s/base` | chart |
|---|---|---|
| `spec.selector.matchLabels` | `app.kubernetes.io/name: quinta-web` | `name: quinta` + `instance: <release>` |

**O `selector` de um Deployment é imutável.** Aplicar o chart por cima do
Deployment existente falha com `field is immutable`. Não é uma questão de
esperar mais tempo nem de forçar o sync.

### Resolução recomendada: apagar e deixar o ArgoCD criar

Apagam-se **apenas** os objetos da aplicação. O namespace, o Postgres, o PVC e
o Secret ficam intactos — os dados não são tocados.

```bash
# 1) confirmar o que vai ser apagado
kubectl get deploy,svc,ingress -n quinta

# 2) apagar só a aplicação (NÃO apagar o statefulset, o pvc nem o secret)
kubectl delete deployment quinta-web -n quinta
kubectl delete service quinta-web -n quinta
kubectl delete ingress quinta-web -n quinta
# se tiveres criado o Ingress catch-all à mão, apaga-o também —
# o chart passa a criá-lo (ingress.catchAll: true)
kubectl get ingress -n quinta

# 3) deixar o ArgoCD criar tudo de novo
kubectl apply -f argocd/
kubectl -n argocd get application quinta -w
```

A aplicação fica indisponível durante alguns segundos, entre o `delete` e o
primeiro sync. Num laboratório é aceitável; em produção far-se-ia com uma
janela de manutenção ou com a alternativa abaixo.

### Alternativa: adoção sem downtime

Alterar `quinta.selectorLabels` no `_helpers.tpl` para emitir exatamente
`app.kubernetes.io/name: quinta-web`, igual ao dos manifests base. Com o
selector coincidente, o ArgoCD aplica por cima e adota os objetos existentes,
sem os recriar.

Custo: o `selectorLabels` deixa de incluir `app.kubernetes.io/instance`, o que
impede duas releases do mesmo chart no mesmo namespace. Aqui não é limitação
nenhuma — dev e prod usam namespaces diferentes — mas afasta-se da convenção
dos charts Helm, e por isso ficou como alternativa e não como recomendação.

### E depois: parar de aplicar à mão

A partir do momento em que o ArgoCD gere a aplicação, `k8s/base/10`, `11` e
`12` deixam de ser aplicados. Continuam no repositório como referência e como
base do overlay de desenvolvimento, mas quem os aplicar à mão volta a criar o
conflito. As bases de dados (`13`, `14`, `30`–`32`) continuam por `kubectl` até
haver uma Application para elas.

---

## 7.5 Aplicar a Application

```bash
kubectl apply -f argocd/
kubectl -n argocd get applications
argocd app get quinta        # se tiveres a CLI instalada
```

Pontos importantes da definição em
[`argocd/quinta-application.yaml`](https://github.com/renatovdsilva/renato-alta-disponibilidade/blob/main/argocd/quinta-application.yaml):

- `repoURL` aponta para o repositório **público** — não são precisas
  credenciais no ArgoCD
- `path: charts/quinta`, `valueFiles: [values-prod.yaml]` — o caminho dos
  values é relativo à pasta do chart
- `prune: true` — apagar do Git apaga do cluster
- `selfHeal: true` — alterações manuais são revertidas
- `CreateNamespace=true` — inofensivo, o namespace já existe

---

## 7.6 Mais do que uma aplicação

O ArgoCD deixa de ser um caso de estudo quando gere mais do que uma coisa.
A partir de 14/08/2026 o repositório aloja três aplicações:

| Aplicação | Namespace | Fonte | Formato |
|---|---|---|---|
| Quinta do Calvário | `quinta` | `charts/quinta` | Helm chart |
| RenatoTrack | `renatotrack` | `k8s/apps/renatotrack` | manifests |
| FitnessPHIVE | `fitness` | `k8s/apps/fitness` | manifests |

**Uma Application por aplicação**, em `argocd/`. Cada uma tem o seu ciclo de
sync, o seu estado de saúde e o seu histórico — um erro numa não bloqueia as
outras, o que não seria verdade com uma Application única a apontar para a raiz
do repositório.

Os dois formatos convivem sem configuração especial. O chart existe onde há
valores por ambiente; onde há um ambiente só, manifests simples chegam. Não há
mérito em converter o que já funciona.

Pré-requisitos manuais de cada uma (Secrets e imagens importadas), o
procedimento de migração e o aviso sobre o self-heal estão em
[`docs/13-aplicacoes-gitops.md`](13-aplicacoes-gitops.md).

> **O que muda no dia a dia:** com três Applications em self-heal, o `kubectl`
> deixa de ser a forma de alterar o cluster. Um `kubectl patch` num recurso
> gerido dura segundos. Foi o que aconteceu ao Ingress catch-all da Quinta, que
> nunca chegou ao Git e desapareceu no primeiro sync.

---

## 7.7 Fluxo de trabalho a partir daqui

```
alterar values.yaml → git commit → git push → ArgoCD sincroniza → cluster atualizado
```

Nunca mais `kubectl apply` para a aplicação. Se for preciso alterar alguma
coisa, altera-se no Git.

Por omissão o ArgoCD verifica o repositório a cada **3 minutos**. Para não
esperar, forçar pela UI (*Refresh* / *Sync*) ou pela CLI:

```bash
argocd app sync quinta
```

---

## 7.8 Demonstração de self-heal

O teste que mostra a diferença entre "aplicar YAML" e GitOps.

```bash
# terminal 1 — observar
kubectl get pods -n quinta -w

# terminal 2 — provocar drift à mão
kubectl scale deployment quinta-web -n quinta --replicas=5
kubectl get deploy quinta-web -n quinta      # 5 réplicas, por instantes
```

O ArgoCD deteta que o cluster já não corresponde ao Git e repõe as 2 réplicas
definidas em `values-prod.yaml`. **Cronometrar** desde o `scale` até o
`kubectl get deploy` voltar a mostrar 2, e registar em `docs/11-metricas.md`.

Segunda variante, mais convincente porque não é um simples número:

```bash
# alterar a imagem à mão para uma tag que não existe
kubectl set image deployment/quinta-web web=quinta-calvario:9.9.9 -n quinta
```

O ArgoCD repõe a tag do Git antes de os pods novos chegarem a falhar — e o
histórico da UI mostra quem alterou o quê.

Para provar o contrário (que o self-heal está mesmo a fazer alguma coisa),
desligá-lo e repetir:

```bash
kubectl -n argocd patch application quinta --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false}}}}'
```

Com `selfHeal: false`, a Application fica `OutOfSync` e o drift permanece —
que é exatamente o estado em que vive um cluster gerido à mão.

---

## Registo

| Data | Ação | Observação |
|---|---|---|
| 12/08/2026 | ArgoCD instalado | **v3.5.0**, manifests oficiais, namespace `argocd`. `deployment "argocd-server" successfully rolled out` |
| 12/08/2026 | acesso à UI | `port-forward` 8081:443, https, `admin` com a password do secret inicial |
| 12/08/2026 | conflito dos dois donos resolvido | apagados `deployment`, `service` e `ingress` `quinta-web`. StatefulSet, PVC e Secret **não** foram tocados — dados intactos |
| 12/08/2026 | Application `quinta` criada | criada às 08:30:34, primeiro sync às 08:30:37 — **3 s** |
| 12/08/2026 | recursos recriados pelo ArgoCD | **61 s** — Deployment 2/2, Service ClusterIP `10.43.65.52`, Ingress em `quinta.localhost` com os 3 IPs dos nós |
| 12/08/2026 | estado da Application | `Healthy` + `Synced`, aplicação validada no browser |
| 12/08/2026 | self-heal testado (réplicas) | `scale --replicas=5` revertido para 2 em **1–2 s** |
| 12/08/2026 | commit e push do chart corrigido | `fullnameOverride`, `securityContext` e Ingress catch-all |
| 13/08/2026 | **ciclo completo validado** | o ArgoCD trocou `quinta-quinta` por `quinta-web` sozinho, a partir do Git. 2/2 réplicas, sem `kubectl` nenhum pelo meio |
| 13/08/2026 | CRD `ApplicationSet` em falta | detetado pela monitorização — 208 reinícios em 24 h. Corrigido com `apply --server-side`. Ver doc 09 |
| | self-heal testado (imagem) | |

### O ciclo completo, validado em 13/08/2026

Este é o momento em que o GitOps deixou de ser configuração e passou a ser
demonstrável.

O chart tinha ficado com os nomes errados (`quinta-quinta`) por uma razão banal
e instrutiva: **as correções estavam na pasta local, não no Git**. O ArgoCD lê
o repositório remoto — o que não foi commitado não existe para ele. Bastou
`git push`.

A partir daí, sem um único `kubectl`:

```
git push → ArgoCD deteta → cria quinta-web → faz prune de quinta-quinta → 2/2 Ready
```

O `prune: true` é a metade que costuma ser esquecida. Sem ele, ficariam os dois
conjuntos de recursos a servir a mesma aplicação: o novo, criado a partir do
Git, e o antigo, órfão e invisível para quem só olha para o repositório.

**A lição a levar:** quando o cluster não corresponde ao que se espera, a
primeira pergunta em GitOps deixa de ser "o que está mal no cluster?" e passa a
ser "o que é que o repositório tem, afinal?". `git status` antes de
`kubectl describe`.

---

### Observações

- **Estabilidade do cluster:** 3 nós `Ready` há **38 horas** sem falhas
  (k3s v1.35.5), incluindo o período com o Postgres e a aplicação a correr.

- **Aviso do `kubectl` ao aplicar a Application:**

  ```
  metadata.finalizers: "resources-finalizer.argocd.argoproj.io": prefer a domain-qualified finalizer name
  ```

  Cosmético. O Kubernetes recomenda finalizers com domínio próprio para evitar
  colisões de nomes; este é o finalizer oficial do ArgoCD e funciona na mesma.
  Não há nada a corrigir do nosso lado.

- **O self-heal foi mais rápido do que a criação dos pods.** A sequência
  observada — 2/5 com 5 desejadas, depois 2/2 com 5, depois 2/2 com 2 — mostra
  que o ArgoCD repôs o valor antes de as réplicas extra chegarem a existir. A
  alteração manual nunca se materializou em pods a correr.

  É a demonstração concreta de que o estado desejado passou a viver no Git: já
  não é o último `kubectl` a ganhar, é o repositório.
