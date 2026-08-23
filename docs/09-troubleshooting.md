# 09 — Troubleshooting

Registo dos problemas encontrados e como foram resolvidos. Esta é a secção mais útil em entrevista.

---

## Método

Por esta ordem, sempre:

```bash
kubectl get pods -n <ns>                                   # 1. qual é o estado
kubectl describe pod <pod> -n <ns>                         # 2. eventos e razão
kubectl logs <pod> -n <ns> [--previous]                    # 3. o que a aplicação disse
kubectl get events -n <ns> --sort-by='.lastTimestamp'      # 4. contexto do cluster
```

---

## Problemas conhecidos

### ImagePullBackOff / ErrImagePull

**Sintoma:** o pod nunca arranca; `describe` mostra `Failed to pull image`.

**Causa no k3d:** a imagem existe no Docker local mas não dentro do cluster.

**Solução:**
```bash
k3d image import <imagem>:<tag> -c alta-disponibilidade
```
E garantir `imagePullPolicy: IfNotPresent` no Deployment.

---

### CrashLoopBackOff

**Sintoma:** o pod arranca e morre em ciclo.

**Diagnóstico:**
```bash
kubectl logs <pod> -n <ns> --previous
```

**Causas mais comuns:** variável de ambiente em falta, porta errada, ficheiro de configuração ausente, base de dados inacessível.

---

### Pod em Pending

**Sintoma:** o pod nunca é agendado.

**Diagnóstico:** `kubectl describe pod` — a secção Events diz a razão.

**Causas:** recursos insuficientes nos nós, PVC por satisfazer, taints sem toleration.

---

### Ingress devolve 404

**Verificar:**
```bash
kubectl get ingress -n <ns>            # tem endereço?
kubectl get svc -n <ns>                # o Service existe?
kubectl get endpoints -n <ns>          # tem endpoints? se vazio, o selector está errado
```

Causa mais frequente: `selector` do Service não coincide com os `labels` do pod.

---

### Cluster não arranca depois de reiniciar o Windows

```bash
k3d cluster start alta-disponibilidade
```
O Docker Desktop tem de estar a correr primeiro.

---

### WSL a consumir toda a RAM

Criar `.wslconfig` (ver `docs/01b-instalacao-ferramentas.md`) e correr `wsl --shutdown`.

---

### `UNC paths are not supported` ao correr scripts npm no WSL

```
UNC paths are not supported. Defaulting to Windows directory.
```

Causa: não havia Node instalado no Ubuntu. O `PATH` do WSL inclui o do Windows
(interop), portanto `node` e `npm` resolviam para os binários do Windows. O npm
do Windows corre os scripts pelo `CMD.EXE`, que não sabe lidar com caminhos
`\\wsl.localhost\...`.

Enganador porque `node -v` respondia normalmente — com a versão do Windows.

```bash
which node npm     # /mnt/c/Program Files/nodejs/... → é o do Windows
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
```

Detalhe em `docs/01b-instalacao-ferramentas.md`, secção 1.5.

---

### `next.config.ts` ignorado ou a dar erro no Next 14

Configuração em TypeScript só é suportada a partir do **Next 15**. No Next 14 o
ficheiro é ignorado — e o sintoma é indireto: o `output: 'standalone'` nunca se
aplica, o `.next/standalone` não é gerado e o build da imagem falha na etapa que
o tenta copiar.

Solução: converter para `next.config.mjs`.

---

### NextAuth devolve 500 em `/api/auth/error` com `NO_SECRET`

Falta a variável `NEXTAUTH_SECRET`. Em desenvolvimento vai para `.env.local`
(que **tem** de estar no `.gitignore`); no cluster vem do Secret `quinta-db`.

```bash
openssl rand -base64 32
```

---

### `prisma migrate dev` falha com P1017 através do port-forward

```
P1017: Server has closed the connection
```

Não é o Postgres a cair. O `migrate dev` cria uma **base de dados sombra** para
validar o schema e, ao criá-la e largá-la, força o fecho das ligações ao
servidor — o que mata o túnel do `kubectl port-forward`.

Contorno: `npx prisma db push`, que não usa base sombra. Custo: não gera
migrações versionadas. Solução definitiva: configurar `shadowDatabaseUrl` no
`schema.prisma`. Ver `docs/03-containerizacao.md`, secção 3.6.

---

### `kubectl port-forward` deixa de funcionar depois de o pod ser recriado

O `port-forward` liga-se a **um pod concreto**. Se o pod for destruído, o túnel
não segue o substituto — fica preso a um destino que já não existe, sem erro
óbvio. Reiniciar o comando.

Encaminhar para o Service (`svc/postgres`) não resolve: o port-forward resolve
o Service para um pod no momento em que arranca e fica agarrado a esse.

---

### Medições através de `port-forward` dão números falsos

Um teste de disponibilidade com `curl` em ciclo contra um
`kubectl port-forward` deu **115 falhas em 290 pedidos — sem qualquer falha
provocada**. Cinco pedidos manuais a seguir devolveram `307 307 307 307 307`:
a aplicação estava saudável.

O `port-forward` é um processo a multiplexar ligações sobre a API do
Kubernetes. Não foi feito para ligações sucessivas rápidas e começa a
recusá-las muito antes de a aplicação sentir seja o que for.

**Nunca medir disponibilidade, latência ou débito através de um port-forward.**
O gerador de carga tem de correr dentro do cluster:

```bash
kubectl run loadgen -n <ns> --rm -it --restart=Never \
  --image=curlimages/curl -- sh -c 'for i in $(seq 1 100); do curl -s -o /dev/null --max-time 2 http://<service>/ || echo FALHA; sleep 0.2; done'
```

Regra geral: quando um resultado é mau, reproduzir à mão antes de acreditar
nele. Um número mau que não se reproduz é quase sempre erro de instrumento.

---

### Aplicação com erros `E57P01` depois de a base de dados reiniciar

```
terminating connection due to administrator command
```

O pool de ligações guardou sockets para um pod que já não existe e continua a
entregá-los à aplicação. O cluster recuperou; o cliente não.

Em desenvolvimento resolve-se reiniciando o servidor. A correção real é do lado
da aplicação: limites de tempo de vida das ligações no pool, validação antes de
usar, e retry com backoff. Ver `docs/04-deploy.md`, secção 4.6.

---

### `COPY /app/public` falha no build da Quinta

O repositório não tem pasta `public/`, e o Docker não permite copiar uma origem
inexistente nem tornar um `COPY` opcional. O Dockerfile passou a criar a pasta
na etapa de build (`RUN mkdir -p /app/public`). Em alternativa, criar
`public/.gitkeep` no repositório da aplicação.

---

### Login do NextAuth fica preso em "A entrar...", sem erro nenhum

O pior problema desta sessão, precisamente por **não produzir erro**: sem
mensagem no browser, sem stack trace, sem nada nos logs do pod. O pedido de
login parte e a sessão nunca se estabelece.

**Contexto:** acesso à aplicação a partir do exterior, por um túnel cloudflared
apontado ao Ingress:

```bash
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80
cloudflared tunnel --url http://localhost:8080
```

**Causa:** o cabeçalho `Host` que a aplicação recebia não correspondia ao
`NEXTAUTH_URL`. O `cloudflared` foi corrido com `--http-host-header quinta.localhost`
para casar com a regra de host do Ingress, portanto a aplicação via
`Host: quinta.localhost`, enquanto o `NEXTAUTH_URL` era o domínio do túnel.

O NextAuth compara as duas coisas para se proteger contra *host header
injection*, e quando divergem recusa estabelecer a sessão — silenciosamente.
A defesa é legítima; a ausência de diagnóstico é que torna isto difícil.

**Solução:** um Ingress adicional **sem `host`** (catch-all), que aceita
qualquer cabeçalho `Host`, e correr o túnel sem o flag:

```bash
cloudflared tunnel --url http://localhost:8080
```

Assim o `Host` que chega à aplicação é o domínio do túnel, igual ao
`NEXTAUTH_URL`.

**Como diagnosticar da próxima vez:** quando a autenticação falha sem erro,
comparar o `Host` efetivamente recebido com o que a aplicação espera.

```bash
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller | tail -20
kubectl exec -n quinta deploy/quinta-web -- env | grep NEXTAUTH
```

> Aplica-se a qualquer proxy à frente da aplicação — Cloudflare, ngrok, um
> balanceador. Reescrever o `Host` é conveniente para encaminhar, e é
> exatamente o que parte a autenticação.

---

### Workflow de documentação falha no `cache: pip`

```
Some specified paths were not resolved, unable to cache dependencies.
```

O `actions/setup-python` com `cache: pip` procura por omissão `requirements.txt`
ou `pyproject.toml` na raiz. Neste repositório o ficheiro chama-se
`requirements-docs.txt`, portanto não encontrava nada e falhava.

```yaml
- uses: actions/setup-python@v5
  with:
    python-version: '3.12'
    cache: pip
    cache-dependency-path: requirements-docs.txt
```

---

### Depois de uma queda: o que o `kubectl` mostra não é o que está a acontecer

Três armadilhas de diagnóstico, todas observadas na recuperação da queda de
energia de 12/08/2026 (ver `docs/08-operacao.md`, secção 8.5).

**1. O `AGE` do `kubectl get nodes` não é tempo de funcionamento.**

Depois do reinício continuava a mostrar `38h`. Não é o nó que está a correr há
38 horas — é a idade do **objeto `Node` no etcd**, que persiste em disco e
sobrevive ao reinício. O objeto tem 38 horas; o processo tem segundos.

Para tempo real de funcionamento:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
# k3d-alta-disponibilidade-server-0   Up 47 seconds
```

Ou, dentro do cluster:

```bash
kubectl get nodes -o custom-columns=NOME:.metadata.name,ARRANQUE:.status.nodeInfo.bootID
uptime          # no host
```

Isto enganou-me a mim primeiro, e é o tipo de detalhe que faz perder meia hora
a investigar a coisa errada.

**2. `Ready` pode ser o último estado conhecido, não o atual.**

Logo após o arranque, o `kubectl get nodes` dava os três nós como `Ready`
quando o `agent-0` ainda estava a reiniciar.

O control plane só marca um nó como `NotReady` ao fim de cerca de **40
segundos** sem receber heartbeat do kubelet. Nessa janela, o que o `kubectl`
devolve é o último estado que conhecia — não a realidade.

Consequência prática: nos primeiros minutos depois de uma queda, confirmar o
estado pela camada de baixo (`docker ps`) antes de acreditar no `kubectl`.

**3. Pods em `Unknown`.**

Os pods do nó afetado passaram por `Unknown` antes de voltarem. Não significa
que o pod falhou nem que a aplicação teve erro: significa que o **control plane
perdeu contacto com o kubelet** que o gere e deixou de saber o que lhe
aconteceu.

`Unknown` é ausência de informação, não uma falha diagnosticada. O control
plane não pode assumir que o pod morreu — pode estar a servir tráfego
normalmente num nó que apenas ficou incomunicável. Por isso não o substitui de
imediato: espera, e só depois de o nó ser dado como perdido é que os pods são
reagendados.

Distinguir dos outros estados:

| Estado | Significa |
|---|---|
| `CrashLoopBackOff` | o container arranca e morre — problema da aplicação |
| `Pending` | não foi agendado — falta de recursos, PVC, taints |
| `Unknown` | o control plane não sabe — problema de comunicação com o nó |

---

### `argocd-applicationset-controller` em CrashLoopBackOff há 24 horas

O incidente mais instrutivo do projeto, porque **não foi descoberto por
ninguém a olhar** — foi a monitorização a encontrá-lo na primeira hora de vida.

**Como apareceu.** A testar os alertas em 13/08/2026, o `KubePodCrashLooping`
estava `firing` — mas não era o pod de teste. Era o
`argocd-applicationset-controller`, em CrashLoopBackOff havia 47 minutos, com
**208 reinícios acumulados em 24 horas**. Falhava desde a instalação do ArgoCD,
no dia anterior, e passou despercebido porque nada do que se usa depende dele.

#### Diagnóstico

```bash
kubectl -n argocd get pods
kubectl -n argocd logs deploy/argocd-applicationset-controller --tail=30
```

De 10 em 10 segundos, sempre o mesmo:

```
failed to get restmapping: no matches for kind "ApplicationSet" in version "argoproj.io/v1alpha1"
  if kind is a CRD, it should be installed before calling Start
```

E ao fim de 2 minutos:

```
failed to wait for applicationset caches to sync ... timed out waiting for cache to be synced
```

O ciclo completo: arranca → procura o tipo de recurso que devia gerir → não
existe → espera pela sincronização da cache → desiste → morre → o kubelet
reinicia. Repetir 208 vezes.

#### Causa raiz: uma anotação grande demais

A tentativa de instalar o CRD em falta revelou o verdadeiro problema:

```bash
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/crds/applicationset-crd.yaml
```

```
The CustomResourceDefinition "applicationsets.argoproj.io" is invalid:
metadata.annotations: Too long: may not be more than 262144 bytes
```

O `kubectl apply` do lado do cliente guarda uma **cópia integral do manifesto**
na anotação `kubectl.kubernetes.io/last-applied-configuration` — é assim que
sabe, na aplicação seguinte, o que apagar e o que manter. O CRD dos
ApplicationSets é grande ao ponto de essa cópia ultrapassar o limite de 256 KB
que o etcd impõe às anotações.

Foi exatamente isto que aconteceu na instalação inicial: o `install.yaml`
aplicou dezenas de objetos com sucesso e **este falhou no meio do output**,
sem parar nada. O ArgoCD ficou a funcionar — Applications, sync, self-heal,
tudo bem — com um controller a morrer em ciclo ao lado.

#### Correção

```bash
kubectl apply --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/crds/applicationset-crd.yaml
kubectl -n argocd rollout restart deploy/argocd-applicationset-controller
kubectl -n argocd get pods -w
```

O `--server-side` faz o merge no servidor: a propriedade dos campos é
registada em `metadata.managedFields` em vez de numa anotação, e por isso não
há limite de tamanho a estourar.

#### O que levar daqui

1. **Um `kubectl apply` de um ficheiro grande pode falhar parcialmente.** O
   código de saída e as últimas linhas do output não contam a história toda —
   confirmar sempre com `kubectl get` o que interessa.
2. **`--server-side` deve ser o omissão para manifests de terceiros**, sobretudo
   os que trazem CRDs. Ver a recomendação no doc 07.
3. **Um componente pode falhar durante dias sem consequência visível.** Só se
   dá por ele quando fizer falta — tipicamente no pior momento.

> Esta entrada é a justificação prática da sessão 5. A monitorização pagou-se
> a si própria antes de o primeiro teste de alerta chegar ao fim.

---

## Registo pessoal

| Data | Problema | Causa | Solução | Tempo perdido |
|---|---|---|---|---|
| 11/08/2026 | Scripts npm falhavam com `UNC paths are not supported` | Node não estava instalado no Ubuntu; o interop do WSL resolvia `node`/`npm` para os binários do Windows (v24.14.1) | Node 20 LTS via NodeSource dentro do Ubuntu | |
| 11/08/2026 | `output: 'standalone'` não produzia efeito | `next.config.ts` não é suportado no Next 14, só a partir do 15 | Convertido para `next.config.mjs` | |
| 11/08/2026 | 500 em `/api/auth/error`, erro `NO_SECRET` | `NEXTAUTH_SECRET` e `NEXTAUTH_URL` não definidas | `.env.local` em desenvolvimento (no `.gitignore`), Secret no cluster | |
| 11/08/2026 | `prisma migrate dev` com P1017 | base de dados sombra força o fecho das ligações e mata o port-forward | `prisma db push`; `shadowDatabaseUrl` fica pendente | |
| 11/08/2026 | Build da Quinta falhava no `COPY /app/public` | a aplicação não tem pasta `public/` | `mkdir -p /app/public` na etapa de build | |
| 11/08/2026 | Aplicação com `E57P01` depois de recriar o `postgres-0` | pool com ligações mortas; port-forward preso ao pod antigo | reinício manual do port-forward e do servidor de dev | |
| 11/08/2026 | Login preso em "A entrar...", **sem erro nenhum** | `Host` reescrito pelo `--http-host-header` do cloudflared não coincidia com o `NEXTAUTH_URL` | Ingress catch-all sem `host` e túnel sem o flag | |
| 11/08/2026 | Workflow `docs.yml` falhava no `cache: pip` | o `setup-python` procura `requirements.txt`; o ficheiro chama-se `requirements-docs.txt` | `cache-dependency-path: requirements-docs.txt` | |
| 12/08/2026 | Queda de energia com o cluster a correr | falha elétrica, desktop sem bateria | recuperação autónoma em ~5 min, sem intervenção; ver doc 08, secção 8.5 | 0 (nada a fazer) |
| 12/08/2026 | `AGE` dos nós mostrava 38h depois do reinício | é a idade do objeto `Node` no etcd, não tempo de funcionamento | usar `docker ps` para uptime real | |
| 13/08/2026 | `argocd-applicationset-controller` com 208 reinícios em 24 h | o CRD `ApplicationSet` nunca foi criado: falhou em silêncio no `install.yaml` por a anotação `last-applied-configuration` exceder os 256 KB do etcd | `kubectl apply --server-side` do CRD e `rollout restart` do controller | **detetado pela monitorização**, não por inspeção |
