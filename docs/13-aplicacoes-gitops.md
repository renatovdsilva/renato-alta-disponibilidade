# 13 — Aplicações geridas por GitOps

Três aplicações, três Applications do ArgoCD, um repositório.

| Aplicação | Namespace | Fonte no Git | Formato | Estado |
|---|---|---|---|---|
| Quinta do Calvário | `quinta` | `charts/quinta` | Helm chart | gerida desde 12/08/2026 |
| RenatoTrack | `renatotrack` | `k8s/apps/renatotrack` | manifests | gerida desde 27/08/2026 |
| FitnessPHIVE | `fitness` | `k8s/apps/fitness` | **Kustomize** | gerida desde 27/08/2026 |

> **Kustomize e o bloco `directory:` não coexistem.** Numa pasta com
> `kustomization.yaml`, declarar `directory:` na Application desliga a deteção
> automática e o ArgoCD passa a tratar o `kustomization.yaml` como um recurso a
> aplicar. Usar `kustomize: {}`. Ver `docs/09-troubleshooting.md`.

O ArgoCD lê charts e manifests simples sem configuração especial. A Quinta usa
chart porque precisa de valores por ambiente; as outras duas têm um ambiente
só, e converter agora seria trabalho sem retorno.

---

## 13.1 Pré-requisitos manuais

O ArgoCD **aplica manifests**. Não constrói imagens, não cria segredos, não
adivinha o que não está no repositório. Tudo o que está nesta secção tem de
existir **antes** do primeiro sync.

### Imagens — nenhuma está em registo

As três imagens são construídas localmente e importadas para os nós. Não há
registo de onde o cluster as possa puxar.

```bash
k3d image import quinta-calvario:1.0.0 -c alta-disponibilidade
k3d image import renatotrack:2.0.1     -c alta-disponibilidade
k3d image import fitnessphive:0.1.0    -c alta-disponibilidade
```

Todos os Deployments têm de usar `imagePullPolicy: IfNotPresent`. Com `Always`,
o kubelet tenta ir buscar a imagem a um registo e fica em `ImagePullBackOff`.

**Consequência para o fluxo GitOps:** mudar a tag da imagem no Git não chega —
é preciso construir e importar a nova tag primeiro. Enquanto não houver
registo, o GitOps aqui é completo para configuração e parcial para imagens.

### Secrets — nenhum está no Git

| Aplicação | Secret | Conteúdo | Como recriar |
|---|---|---|---|
| Quinta | `quinta-db` | credenciais do Postgres, `NEXTAUTH_SECRET`, `NEXTAUTH_URL` | `k8s/examples/postgres-secret.example.yaml` |
| RenatoTrack | `renatotrack-postgres` | credenciais do Postgres próprio | `k8s/examples/renatotrack-secret.example.yaml` |
| FitnessPHIVE | `fitness-basic-auth` | `htpasswd` da autenticação básica | `k8s/examples/fitness-secrets.example.md` |
| FitnessPHIVE | `fitness-tls` | certificado de `fitness.localhost` | idem |
| FitnessPHIVE | `fitness-tls-public` | certificado de `renatovdsilva.ddns.net` | idem |

Verificação antes de sincronizar:

```bash
kubectl -n quinta       get secret quinta-db
kubectl -n renatotrack  get secret renatotrack-postgres
kubectl -n fitness      get secret fitness-basic-auth fitness-tls fitness-tls-public
```

Se algum faltar, os pods ficam em `CreateContainerConfigError` — falha à vista,
que é o comportamento certo.

---

## 13.2 O aviso que interessa: com self-heal, o `kubectl` deixa de contar

A partir do momento em que uma Application gere um conjunto de recursos com
`selfHeal: true`, **qualquer alteração feita com `kubectl` a esses recursos é
revertida** em segundos. Não é um efeito secundário: é a função do ArgoCD.

Já aconteceu neste projeto. O Ingress catch-all da Quinta foi criado à mão,
nunca foi para o Git, e desapareceu na primeira sincronização — o ArgoCD
aplicou o que o repositório dizia, e o repositório não o mencionava.

### O que isto implica para estas duas aplicações

**FitnessPHIVE — o caso crítico.** O Ingress `fitnessphive-public` foi corrigido
com `kubectl` depois de criado, em dois pontos:

| Correção | De | Para |
|---|---|---|
| Porta do backend | `port: { name: http }` | `port: { number: 80 }` |
| `auth-realm` | texto com acentos | texto sem acentos |

Se os manifests no Git tiverem a versão antiga, o primeiro sync **repõe a
versão partida**. E o resultado não é apenas um Ingress errado: o webhook de
validação do NGINX rejeita-o, a Application fica em erro de sync, e o acesso
público deixa de funcionar.

Ordem correta: **corrigir o ficheiro primeiro, sincronizar depois.**

```bash
# como está agora no cluster — é isto que tem de ir para o ficheiro
kubectl -n fitness get ingress fitnessphive-public -o yaml
```

**RenatoTrack.** Sem correções manuais conhecidas, mas vale a mesma regra:
qualquer ajuste feito com `kubectl` desde a criação tem de estar nos ficheiros
antes do primeiro sync. Comparar o que está no cluster com o que está nos
manifests de origem é um passo obrigatório, não uma precaução opcional.

**Ambas.** O `spec.selector` de um Deployment é imutável. Se o do ficheiro não
for idêntico ao que está a correr, o sync falha com `field is immutable` e é
preciso apagar e recriar o Deployment — com downtime. Foi o que aconteceu na
migração da Quinta.

### A mudança de hábito

Depois desta migração, `kubectl edit` e `kubectl patch` sobre recursos geridos
passam a ser, na melhor das hipóteses, inúteis. O ciclo passa a ser:

```
alterar ficheiro → git commit → git push → ArgoCD aplica
```

Para uma intervenção urgente sem passar pelo Git, desliga-se a automação
explicitamente:

```bash
kubectl -n argocd patch application <nome> --type merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
# ... intervenção ...
kubectl -n argocd patch application <nome> --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

Voltar a ligar a automação repõe o estado do Git — o que também serve de
mecanismo de reversão, sem ter de lembrar qual era a configuração anterior.

---

## 13.3 Ordem de migração

Uma aplicação de cada vez. Se as duas forem migradas ao mesmo tempo e algo
correr mal, fica-se sem saber qual delas causou o quê.

```bash
cd ~/Documents/renato-alta-disponibilidade

# 1) copiar os manifests (ver os README de cada pasta)
cp ~/Documents/RenatoTrack/deploy/k8s/*.yaml   k8s/apps/renatotrack/
cp ~/Documents/FitnessPHIVE/deploy/k8s/*.yaml  k8s/apps/fitness/

# 2) REMOVER os Secrets que vieram no meio
rm -f k8s/apps/renatotrack/*secret*.yaml k8s/apps/fitness/*secret*.yaml
grep -ril "kind: Secret" k8s/apps/          # tem de devolver vazio

# 3) corrigir o Ingress público do Fitness (ver 13.2)

# 4) confirmar que os ficheiros correspondem ao cluster
kubectl -n renatotrack get deploy,svc,ingress,statefulset -o yaml | less
kubectl -n fitness     get deploy,svc,ingress,pvc         -o yaml | less

# 5) commit e push — o ArgoCD só vê o que está no remoto
git add k8s/apps argocd
git commit -m "GitOps: RenatoTrack e FitnessPHIVE"
git push

# 6) uma aplicação de cada vez
kubectl apply -f argocd/renatotrack-application.yaml
kubectl -n argocd get application renatotrack -w
# confirmar Healthy + Synced e a aplicação a responder antes de continuar

kubectl apply -f argocd/fitness-application.yaml
kubectl -n argocd get application fitness -w
```

O passo 5 não é burocracia: o ArgoCD lê o repositório **remoto**. Alterações
que fiquem na pasta local não existem para ele — foi assim que os recursos da
Quinta ficaram com o nome errado durante um dia.

---

## Registo

| Data | Aplicação | Ação | Observação |
|---|---|---|---|
| 12/08/2026 | Quinta | migrada para ArgoCD | primeira; obrigou a apagar e recriar por causa do selector imutável |
| 27/08/2026 | RenatoTrack | migrada | sync à primeira, sem incidentes |
| 27/08/2026 | FitnessPHIVE | migrada | cinco correções antes do primeiro sync — ver doc 09 |

**Estado em 27/08/2026:** as três `Synced` e `Healthy`, em três formatos
diferentes (Helm, manifests simples e Kustomize).
