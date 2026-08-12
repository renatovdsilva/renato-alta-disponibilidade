# 04 — Deploy no Kubernetes

## 4.1 Objetos usados e porquê

| Objeto | Função |
|---|---|
| **Namespace** | isolar cada aplicação; facilita quotas, RBAC e limpeza |
| **Deployment** | gerir réplicas e rollouts sem downtime |
| **Service** | endereço estável e balanceamento entre pods |
| **Ingress** | entrada HTTP por host, uma única porta para várias aplicações |
| **StatefulSet** | as bases de dados — identidade e volume estáveis por réplica |
| **Service headless** | DNS por pod (`postgres-0.postgres...`), sem IP virtual |
| **Secret** | credenciais das bases de dados, criadas fora do Git |

---

## 4.2 Decisões tomadas nos manifests

**Réplicas: 2.** Uma réplica não é alta disponibilidade. Com duas, matar um pod não derruba o serviço — e isso é demonstrável.

**Requests e limits.** Sem `requests`, o scheduler não sabe onde colocar o pod. Sem `limits`, uma aplicação com fuga de memória derruba o nó.

```yaml
resources:
  requests: { cpu: 100m, memory: 128Mi }
  limits:   { cpu: 500m, memory: 512Mi }
```

**Liveness e readiness.** São coisas diferentes:
- `readiness` — "já posso receber tráfego?" Se falhar, o pod sai do Service mas continua vivo.
- `liveness` — "ainda estou funcional?" Se falhar, o kubelet reinicia o container.

**`imagePullPolicy: IfNotPresent`.** Necessário porque as imagens são locais, importadas via `k3d image import`. Com `Always` o cluster tentava ir buscar a um registo remoto e falhava.

**Duas réplicas só passaram a ser possíveis depois de trocar o SQLite.** A
Quinta usava um ficheiro SQLite local. Com duas réplicas isso dá ou duas bases
divergentes, ou corrupção por escrita concorrente sobre um volume partilhado —
ver decisão **D9**. É um caso concreto de uma coisa que se repete: alta
disponibilidade não se resolve só na camada de orquestração. Escalar uma
aplicação que guarda estado localmente não a torna disponível, torna-a
inconsistente.

**Credenciais por `secretKeyRef`, não `envFrom`.** Nos dois Deployments as
chaves são listadas uma a uma. O Secret do MySQL também tem a password de root,
que só o servidor precisa de ver — com `envFrom` ela apareceria dentro do pod
da aplicação sem necessidade nenhuma.

**Variáveis injetadas na Quinta:**

| Variável | Origem | Sem ela |
|---|---|---|
| `DATABASE_URL` | Secret `quinta-db` | o Prisma não liga a nada |
| `NEXTAUTH_SECRET` | Secret `quinta-db` | 500 em `/api/auth/error`, erro `NO_SECRET` |
| `NEXTAUTH_URL` | Secret `quinta-db` | callbacks de login para o host errado |

O `NEXTAUTH_URL` é o host do **Ingress** (`http://quinta.localhost`), não o
`localhost:3002` usado em desenvolvimento. É o valor que o NextAuth usa para
construir os URLs de callback: com o secret certo e este errado, o login parte
à mesma — e o sintoma (redirecionamento para um host inexistente) não aponta
para a variável.

Cada ambiente precisa do seu Secret, porque este valor muda: em dev o host é
`quinta-dev.localhost` (ver `charts/quinta/values-dev.yaml`).

---

## 4.3 Aplicar

**A ordem importa.** As aplicações dependem de Secrets e das bases de dados; um
`kubectl apply -f k8s/base/` a seco cria pods que ficam em `CreateContainerConfigError`
à espera de Secrets que não existem.

```bash
cd ~/Documents/renato-alta-disponibilidade

# 1) namespaces
kubectl apply -f k8s/base/00-namespaces.yaml

# 2) Secrets — criados à mão, nunca commitados (D7).
#    Comandos completos em docs/03-containerizacao.md, secções 3.6 e 3.7.

# 3) bases de dados, e esperar que fiquem prontas
kubectl apply -f k8s/base/13-postgres-service.yaml -f k8s/base/14-postgres-statefulset.yaml
kubectl apply -f k8s/base/30-mysql-service.yaml -f k8s/base/32-mysql-schema-configmap.yaml -f k8s/base/31-mysql-statefulset.yaml
kubectl -n quinta rollout status statefulset/postgres
kubectl -n briosa rollout status statefulset/mysql

# 4) migração do Prisma (só na primeira vez) — ver 3.6

# 5) aplicações
kubectl apply -f k8s/base/
kubectl get pods -n quinta -w
```

Depois da primeira vez, o `kubectl apply -f k8s/base/` do passo 5 chega para
tudo: os objetos já existem e a operação é idempotente.

### Porque é que as aplicações não esperam pela base de dados

Não há initContainer a bloquear o arranque à espera do Postgres ou do MySQL.
É deliberado: o `readinessProbe` já trata disso. Um pod que não consiga falar
com a base de dados falha a probe, sai do Service e não recebe tráfego — e
volta sozinho quando a base aparecer. Um initContainer só adiantaria o mesmo
resultado, com mais uma peça para manter.

O que **não** se deve fazer é pôr a probe a devolver OK sem verificar a base:
o pod entrava no balanceamento e servia erros.

---

## 4.4 Aceder

```bash
kubectl get ingress -A
```

No browser do Windows: `http://quinta.localhost`

Se não resolver, acrescentar ao ficheiro `C:\Windows\System32\drivers\etc\hosts`:

```
127.0.0.1 quinta.localhost
127.0.0.1 briosa.localhost
```

---

## 4.5 Teste de resiliência

Este teste é o que se conta em entrevista.

```bash
# terminal 1 — observar
kubectl get pods -n quinta -w

# terminal 2 — matar um pod
kubectl delete pod -n quinta -l app=quinta-web --field-selector status.phase=Running

# terminal 3 — verificar que o site continua a responder
while true; do curl -s -o /dev/null -w "%{http_code}\n" http://quinta.localhost; sleep 1; done
```

**Registar:** quantos pedidos falharam durante a substituição do pod.

---

## 4.6 Teste de persistência da base de dados

Feito em 11/08/2026 contra o `postgres-0`. A pergunta não é se o pod volta — é
se os dados voltam com ele.

```bash
# terminal 1 — observar
kubectl get pods -n quinta -w

# terminal 2 — destruir o pod da base de dados
kubectl delete pod postgres-0 -n quinta
```

**Resultado medido:**

| Momento | Estado |
|---|---|
| 0 s | `Pending` → `ContainerCreating` |
| 2 s | `Running` |
| 6 s | `Ready` (1/1) |

Recuperação total em **6 segundos**, com os dados intactos — a aplicação voltou
a mostrar tudo depois de reposto o acesso.

### `Running` não é `Ready`

A distinção entre os 2 s e os 6 s é a parte que interessa. Aos 2 s o container
estava a correr, mas o Postgres ainda estava a arrancar e não aceitava
ligações. Só aos 6 s a `readinessProbe` (`pg_isready`) passou.

O Kubernetes usa essa diferença para decidir encaminhamento: enquanto a probe
não passa, o pod fica fora dos endpoints do Service e não recebe tráfego. Sem
readiness probe, os quatro segundos intermédios seriam quatro segundos a
encaminhar pedidos para uma base que ainda não responde — e o utilizador via
erros durante um evento que devia ser transparente.

### Lição: o cluster recuperou, os clientes não

Este é o resultado mais útil do teste, e não estava previsto.

O Kubernetes fez o seu trabalho em 6 segundos. Do lado dos clientes, nada
recuperou sozinho:

| Cliente | O que aconteceu |
|---|---|
| Aplicação (pool do Prisma) | ficou com ligações mortas na pool: `E57P01 — terminating connection due to administrator command` |
| `kubectl port-forward` | ficou preso ao pod destruído; o túnel deixou de encaminhar para lado nenhum |

Foi preciso reiniciar o port-forward **e** o servidor de desenvolvimento à mão.

**A conclusão a reter:** alta disponibilidade do lado do orquestrador não
chega. Um pool de ligações guarda sockets abertos para um endereço que deixou
de existir, e continua a entregá-los à aplicação até alguém detetar que estão
mortos. Quem tem de saber reconectar é o cliente.

Do lado da aplicação, o que resolve isto é configuração de pool — limites de
tempo de vida das ligações, validação antes de usar, e retry com backoff nas
operações. Do lado da infraestrutura, um `PodDisruptionBudget` e mais réplicas
reduzem a janela, mas não eliminam o problema: alguém vai apanhar uma ligação
morta.

Fica como pendência de aplicação, não de cluster.

> O `port-forward` preso é um artefacto de desenvolvimento, não um problema de
> produção — em produção o tráfego passa pelo Ingress e pelo Service, que
> seguem os endpoints. Mas serve de aviso: um túnel aberto não é uma ligação
> com alta disponibilidade, e testes feitos através dele podem enganar.

---

## 4.7 Acesso a partir do exterior

O cluster corre em WSL2, sem IP público. Para mostrar a aplicação a alguém de
fora usou-se um túnel:

```bash
# terminal 1 — expor o Ingress na máquina
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80

# terminal 2 — túnel público
cloudflared tunnel --url http://localhost:8080
```

Testado com sucesso por outra pessoa, de outra rede, em 11/08/2026.

**Sem `--http-host-header`.** A tentação é passar
`--http-host-header quinta.localhost` para casar com a regra de host do
Ingress. Funciona para servir páginas e **parte a autenticação**: o NextAuth
compara o `Host` recebido com o `NEXTAUTH_URL` e recusa a sessão em silêncio,
sem erro nenhum. Ver `docs/09-troubleshooting.md`.

A solução foi um Ingress **catch-all**, sem `host`, que aceita qualquer
cabeçalho e encaminha para o mesmo Service. Com ele o túnel corre sem flags e
a aplicação recebe o `Host` do domínio público — o mesmo que está no
`NEXTAUTH_URL`.

> Isto é uma montagem de demonstração, não de produção. Um túnel expõe a
> aplicação à internet sem WAF, sem rate limiting e com credenciais de teste.
> Serve para mostrar o trabalho a alguém e deve ser desligado a seguir.

---

## 4.8 Rollout e rollback

```bash
kubectl set image deployment/quinta-web web=quinta-calvario:1.1.0 -n quinta
kubectl rollout status deployment/quinta-web -n quinta
kubectl rollout history deployment/quinta-web -n quinta
kubectl rollout undo deployment/quinta-web -n quinta
```

---

## Registo

| Data | Ação | Observação |
|---|---|---|
| 11/08/2026 | Secret `quinta-db` criado | por linha de comandos, com password gerada por `openssl`. Nenhuma credencial passou por ficheiro |
| 11/08/2026 | PostgreSQL aplicado | `postgres-0` `1/1 Running` — PostgreSQL 16.14 em Alpine |
| 11/08/2026 | Service headless | `CLUSTER-IP: None`, porta 5432 |
| 11/08/2026 | PVC `data-postgres-0` | `Bound`, 2 Gi, RWO, storageclass `local-path` |
| 11/08/2026 | teste de persistência | `delete pod postgres-0` → `Running` aos 2 s, `Ready` aos **6 s**, dados intactos |
| 11/08/2026 | `k3d image import quinta-calvario:1.0.0` | **6 s** para os 3 nós |
| 11/08/2026 | primeiro deploy da Quinta | `quinta-web` com 2 réplicas, agendadas em **nós diferentes** (agent-0 e agent-1). Service e Ingress aplicados, aplicação acessível e login funcional |
| 11/08/2026 | rolling update (2×) | `kubectl rollout restart` — sempre com uma réplica a servir, **zero downtime** |
| 11/08/2026 | acesso externo | túnel cloudflared sobre o Ingress; testado com sucesso por outra pessoa, de outra rede |
| | teste de resiliência das aplicações | pedidos falhados: |
