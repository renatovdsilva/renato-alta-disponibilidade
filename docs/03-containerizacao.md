# 03 — Containerização das aplicações

## Aplicações a containerizar

| Aplicação | Stack | Repositório |
|---|---|---|
| Quinta do Calvário | Next.js 14, TypeScript, Prisma, PostgreSQL *(migrado de SQLite — D9)* | github.com/renatovdsilva/quintadocalvario |
| Briosa Agenda | PHP | github.com/renatovdsilva/briosatecnica-agenda |

---

## 3.1 Princípios usados

1. **Multi-stage build** — a imagem final não leva ferramentas de compilação nem dependências de desenvolvimento.
2. **Imagem base alpine** — menor superfície e menos CVEs.
3. **Utilizador não-root** — o container nunca corre como root.
4. **`.dockerignore`** — evita copiar `node_modules`, `.git` e ficheiros de ambiente para dentro da imagem.
5. **Tag explícita** — nunca `latest`; sempre versão semântica.

---

## 3.2 Quinta do Calvário

Ficheiro: [`apps/quinta-calvario/Dockerfile`](https://github.com/renatovdsilva/renato-alta-disponibilidade/blob/main/apps/quinta-calvario/Dockerfile)

### Estado do repositório

Levantado em 11/08/2026. Next 14.2, React 18.3, Prisma 5.14, NextAuth 4.24.
Na raiz: `app/`, `components/`, `lib/`, `prisma/`, `middleware.ts`,
`next.config.mjs`, `package.json`, mais dois scripts de Windows
(`instalar.bat`, `push-github.bat`) que não têm nada que fazer numa imagem
Linux — excluídos pelo `.dockerignore`.

### Pendências resolvidas antes do build

| Pendência | Estado |
|---|---|
| Node.js dentro do Ubuntu | **resolvido em 11/08** — não existia; o `npm` era o do Windows. Ver `01b-instalacao-ferramentas.md`, 1.5 |
| `next.config.ts` não suportado no Next 14 | **resolvido** — convertido para `next.config.mjs` |
| `output: 'standalone'` | feito, já no `.mjs` |
| `NEXTAUTH_SECRET` / `NEXTAUTH_URL` em falta | **resolvido** — `.env.local` em dev, Secret no cluster |
| `package-lock.json` inexistente | **por gerar** — `npm ci` não corre sem ele |
| Datasource do Prisma em `sqlite` | **migrar para `postgresql`** com `env("DATABASE_URL")` — decisão D9 |

### A aplicação foi executada antes de ser containerizada

Em 11/08/2026 a Quinta correu pela primeira vez, fora do Docker: Next 14.2.35
*Ready* em 2.1 s, Prisma Client 5.22.0, `prisma db push` a criar a base, seed a
criar o `admin@quintacalvario.pt`, login autenticado e dashboard a renderizar
com 5 quartos.

Vale a pena registar a ordem, porque é a que poupa tempo: **primeiro a correr
na máquina, depois em Docker, depois em Kubernetes**. Cada camada acrescenta
uma classe de erros nova. Saltar direto para o cluster obriga a distinguir um
bug da aplicação de um problema de imagem ou de um problema de rede do
Kubernetes — tudo ao mesmo tempo, com logs de pod pelo meio.

O `next.config.ts` é o exemplo perfeito: o sintoma teria aparecido como um
`COPY` a falhar no Dockerfile, sem relação aparente com a versão do Next.

O `npm ci` exige lockfile e falha sem ele. É de propósito que o Dockerfile usa
`npm ci` e não `npm install`: sem lockfile, duas imagens construídas com dias
de intervalo podem levar versões diferentes das dependências, e a imagem deixa
de ser reprodutível — que é metade do argumento para usar contentores.

> **Dívida técnica (DT1):** o `next.config.mjs` mantém
> `eslint.ignoreDuringBuilds: true` e `typescript.ignoreBuildErrors: true`. O
> build passa mesmo com erros de tipos. Fica assim para desbloquear a
> containerização, mas é o primeiro a corrigir quando houver CI — senão
> publica-se uma imagem com código que não compila, e a falha só aparece em
> runtime.

### Estrutura do multi-stage

Três etapas, cada uma com uma razão:

| Etapa | Faz | Porquê separada |
|---|---|---|
| `deps` | `npm ci` | só volta a correr se o `package*.json` mudar — o resto do código não invalida a cache das dependências |
| `builder` | `prisma generate` + `npm run build` | o `prisma generate` tem de vir **antes** do build: o Next compila código que importa `@prisma/client`, e o cliente só existe depois de gerado |
| `runner` | copia `standalone`, `static`, `public`, `prisma` | não leva toolchain, nem código-fonte, nem `node_modules` de desenvolvimento |

O `output: 'standalone'` é o que torna a última etapa pequena: o Next produz
um bundle que já traz apenas as dependências que o servidor usa em runtime.

### Build e medição

```bash
cd ~/projects/quintadocalvario

# 1) baseline — ANTES de existir .dockerignore
time docker build -f Dockerfile.baseline -t quinta-calvario:baseline .

# 2) multi-stage
time docker build -t quinta-calvario:1.0.0 .

docker images | grep quinta-calvario
```

A baseline usa `node:20` (Debian) numa etapa só, com `node_modules` completo e
código-fonte. **É aqui que o número do currículo é legítimo** — ao contrário da
Briosa, esta é uma comparação multi-stage a sério. Registar em
`docs/11-metricas.md`.

---

## 3.3 Briosa Agenda

Ficheiro: [`apps/briosa-agenda/Dockerfile`](https://github.com/renatovdsilva/renato-alta-disponibilidade/blob/main/apps/briosa-agenda/Dockerfile)

### Estrutura real do repositório

O levantamento feito em 11/08/2026 mostrou que o Dockerfile escrito na sessão
de planeamento estava errado: assumia `public_html/` na raiz, mas **o código
está aninhado em `public_html/public_html/`**. Na raiz existem apenas
`public_html/` e um `public_html.zip` duplicado.

```
public_html/public_html/     ← document root
├── index.php
├── gera_senha.php
├── error_log
├── views/
└── app/
    ├── config/{app.php, database.php}
    ├── database/schema.sql
    ├── src/{Controllers, Core, Models}
    ├── templates/
    └── views/
```

São três controllers (Agenda, Auth, Dashboard), o Core com Auth, Csrf,
Database, View e helpers, e o model User. MVC escrito à mão, sem Composer —
não há passo de instalação de dependências, o que simplifica a imagem.

Base de dados: **MySQL**, `127.0.0.1:3306` no config. Extensão necessária:
`pdo_mysql`.

### Problemas encontrados

| # | Problema | Gravidade | Tratamento |
|---|---|---|---|
| 1 | Password da base de dados em texto limpo em `app/config/database.php`, num repositório **público** | crítica | credencial rodada; ficheiro sai do repo e passa a ler variáveis de ambiente vindas de um Secret |
| 2 | Nome da base divergente: config diz `briosate_agenda`, `schema.sql` cria `agenda_briosa` | alta | fixado `agenda_briosa`; falta corrigir o config |
| 3 | `public_html.zip`, ficheiros `error_log` e `gera_senha.php` entrariam na imagem | média | `.dockerignore` |
| 4 | Charset `utf8` no config contra `utf8mb4` no schema | média | `utf8mb4` nos dois; servidor arranca já com esse valor |
| 5 | `app/` dentro do document root — config e schema alcançáveis por HTTP | média | bloqueado no Apache; correção real é reestruturar a aplicação |

Detalhe e checklist em
[`apps/briosa-agenda/README.md`](https://github.com/renatovdsilva/renato-alta-disponibilidade/blob/main/apps/briosa-agenda/README.md).

> Rodar a password não fecha o problema 1: enquanto o ficheiro estiver no
> histórico do Git, a password antiga continua legível nos commits anteriores.
> Trocar primeiro, reescrever o histórico depois.

### Não-root exige mudar a porta

O princípio 3 desta secção diz que o container nunca corre como root. Com
`php:8.2-apache` isso obriga a uma alteração que não é óbvia: um processo
não-root não se pode ligar a portas abaixo de 1024, portanto o Apache passa a
escutar na **8080**. O `containerPort` do Deployment acompanha; o Service não
muda, porque aponta para o `targetPort` nomeado `http`.

O Dockerfile original tinha `USER www-data` **e** `EXPOSE 80` — combinação que
não arranca. Ficou apanhado na revisão, antes de qualquer build.

### Aqui o ganho não vem do multi-stage

Na Quinta, o multi-stage é o que corta a imagem: separa compilação de execução.
Na Briosa não há compilação nenhuma — é PHP interpretado, sem Composer. Além
disso o `php:8.2-apache` só existe em Debian; não há variante Alpine com Apache.

A comparação honesta é outra: **o que a imagem deixa de levar**. A baseline
copia o repositório inteiro (incluindo o zip) e não limpa a cache do apt; a
versão final tem `.dockerignore`, `docker-php-source delete` e limpeza do apt.
A redução medida é essa, e é assim que deve ser descrita no currículo — não
como multi-stage, que aqui não se aplica.

```bash
cd ~/projects/briosatecnica-agenda

# 1) baseline — ANTES de existir .dockerignore, senão a medição fica falseada
docker build -f Dockerfile.baseline -t briosa-agenda:baseline .

# 2) versão corrigida, já com .dockerignore
docker build -t briosa-agenda:1.0.0 .

docker images | grep briosa-agenda
```

---

## 3.4 Importar imagens para o cluster

O k3d não vê o registo local do Docker. É preciso importar:

```bash
k3d image import quinta-calvario:1.0.0 -c alta-disponibilidade
k3d image import briosa-agenda:1.0.0 -c alta-disponibilidade
```

> **Erro mais comum do projeto:** esquecer este passo resulta em `ImagePullBackOff`. Ver `docs/09-troubleshooting.md`.

---

## 3.5 Verificar a imagem antes de fazer deploy

```bash
docker run --rm -p 3000:3000 quinta-calvario:1.0.0
docker run --rm -p 8081:8080 briosa-agenda:1.0.0
```

Abrir `http://localhost:3000` e `http://localhost:8081`. Se não funcionar em Docker, não vai funcionar em Kubernetes.

A Briosa sem base de dados deve mostrar a página de login ou um erro de ligação
tratado — se devolver um 500 do Apache, o problema é da imagem, não do MySQL.

---

## 3.6 Base de dados da Quinta

PostgreSQL como StatefulSet — decisão **D9** em `docs/10-decisoes.md`. Substitui
o SQLite, que prendia a Quinta a uma réplica. Manifests em
`k8s/base/13-postgres-service.yaml` e `14-postgres-statefulset.yaml`.

**Passo 1 — alterar o datasource** em `prisma/schema.prisma`:

```prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}
```

**Passo 2 — Secret e Postgres no cluster.** A password entra em dois sítios
(chave própria e dentro do URL), por isso gera-se primeiro para uma variável:

```bash
cd ~/Documents/renato-alta-disponibilidade

PGPASS="$(openssl rand -base64 24 | tr -d '/+=')"

kubectl create secret generic quinta-db -n quinta \
  --from-literal=POSTGRES_DB=quinta \
  --from-literal=POSTGRES_USER=quinta \
  --from-literal=POSTGRES_PASSWORD="$PGPASS" \
  --from-literal=DATABASE_URL="postgresql://quinta:${PGPASS}@postgres-0.postgres.quinta.svc.cluster.local:5432/quinta?schema=public"

kubectl apply -f k8s/base/13-postgres-service.yaml
kubectl apply -f k8s/base/14-postgres-statefulset.yaml
kubectl -n quinta rollout status statefulset/postgres
```

O `tr -d '/+='` tira carateres que teriam de ser escapados dentro do URL.

**Passo 3 — migração inicial.** As migrações do Prisma correm contra a base a
partir da máquina de desenvolvimento. Como o Postgres está dentro do cluster,
abre-se um túnel:

```bash
# terminal 1 — túnel para o Postgres do cluster
kubectl port-forward -n quinta svc/postgres 5432:5432

# terminal 2 — no repositório da aplicação
cd ~/projects/quintadocalvario
PGPASS=$(kubectl get secret quinta-db -n quinta -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
export DATABASE_URL="postgresql://quinta:${PGPASS}@127.0.0.1:5432/quinta?schema=public"

npx prisma db push                    # ver nota abaixo sobre o migrate dev
npm run db:seed                       # dados de teste
```

> As migrações do SQLite não se reaproveitam: os tipos não são os mesmos. O
> schema é aplicado de raiz contra o Postgres.

### `prisma migrate dev` não funciona através do port-forward

Tentativa inicial com `npx prisma migrate dev --name init`:

```
P1017: Server has closed the connection
```

Não é um problema de rede nem do Postgres. O `migrate dev` cria uma **base de
dados sombra** — uma base temporária onde aplica as migrações de raiz para
detetar divergências no schema. Ao criá-la e largá-la, força o fecho das
ligações existentes ao servidor. Isso mata o túnel do `kubectl port-forward`, e
o Prisma vê o resultado como servidor a fechar a ligação.

Contornado com `prisma db push`, que aplica o schema diretamente e **não usa
base sombra**:

```bash
npx prisma db push
```

**Custo assumido:** o `db push` não gera ficheiros de migração. Fica-se sem
histórico versionado do schema, que é exatamente o que o GitOps precisa — sem
migrações em Git não há forma de o ArgoCD, ou qualquer pipeline, aplicar
alterações de schema de forma reprodutível.

**Pendente:** configurar `shadowDatabaseUrl` no `schema.prisma`, apontando para
uma segunda base no mesmo servidor, e voltar a gerar as migrações com
`migrate dev`. Depois disso, quem as aplica em produção é `prisma migrate deploy`
(num Job ou initContainer), nunca `migrate dev`.

### Resultado

Migração SQLite → PostgreSQL concluída em 11/08/2026: `db push` aplicou o
schema, o seed correu contra o Postgres, o login com `admin@quintacalvario.pt`
funciona e o dashboard renderiza com dados vindos do cluster.

---

## 3.7 Base de dados da Briosa

O MySQL corre no cluster como StatefulSet — decisão D8 em `docs/10-decisoes.md`.
Manifests em `k8s/base/30-mysql-service.yaml`, `31-mysql-statefulset.yaml` e
`32-mysql-schema-configmap.yaml` (este último é gerado).

Ordem de aplicação, porque há dependências entre eles:

```bash
# 1) Secret — criado à mão, nunca commitado (D7)
kubectl create secret generic briosa-db -n briosa \
  --from-literal=DB_HOST=mysql-0.mysql.briosa.svc.cluster.local \
  --from-literal=DB_PORT=3306 \
  --from-literal=DB_NAME=agenda_briosa \
  --from-literal=DB_CHARSET=utf8mb4 \
  --from-literal=DB_USER=briosa \
  --from-literal=DB_PASSWORD="$(openssl rand -base64 24)" \
  --from-literal=MYSQL_ROOT_PASSWORD="$(openssl rand -base64 24)"

# 2) ConfigMap com o schema, gerado a partir do repositório da aplicação
./scripts/gen-mysql-schema.sh

# 3) MySQL
kubectl apply -f k8s/base/30-mysql-service.yaml
kubectl apply -f k8s/base/32-mysql-schema-configmap.yaml
kubectl apply -f k8s/base/31-mysql-statefulset.yaml
kubectl -n briosa rollout status statefulset/mysql
```

> O `/docker-entrypoint-initdb.d` só corre na **primeira** inicialização, com o
> datadir vazio. Alterar o schema depois disso não tem efeito nenhum — é preciso
> apagar o pod **e o PVC** (`kubectl delete pvc data-mysql-0 -n briosa`) para
> voltar a partir do zero. É a pegadinha clássica desta montagem.

Recuperar a password gerada, se for preciso:

```bash
kubectl get secret briosa-db -n briosa -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
```

---

## Registo

| Aplicação | Versão | Tamanho | Tempo de build | Data |
|---|---|---|---|---|
| quinta-calvario | baseline (single-stage, `node:20`) | **3,4 GB** | | 11/08/2026 |
| quinta-calvario | 1.0.0 (multi-stage + `.dockerignore`) | **282 MB** | ~54 s com cache de camadas | 11/08/2026 |
| briosa-agenda | baseline | | | |
| briosa-agenda | 1.0.0 | | | |

**Redução de 92% — imagem 12 vezes mais pequena.** Detalhe do build otimizado:
`npm run build` 26,7 s, `npx prisma generate` 2,0 s. O `package-lock.json`
gerado tem 35 862 bytes e fixa 81 pacotes.

De onde vem a diferença, por ordem de peso:

1. **Separar build de runtime.** A baseline leva o `node_modules` completo (com
   dependências de desenvolvimento), o código-fonte e o `.next` inteiro. A
   final leva o bundle `standalone`, que só traz o que o servidor usa.
2. **`node:20-alpine` em vez de `node:20`.** A imagem base Debian ronda os
   1,1 GB descomprimidos; a Alpine anda pelos 130 MB.
3. **`.dockerignore`.** Impede que `node_modules` e `.next` locais entrem
   sequer no contexto de build.

### Erro encontrado: `COPY /app/public` falhava

A Quinta **não tem pasta `public/`**. O `COPY --from=builder /app/public ./public`
falha com "not found" — o Docker não deixa copiar uma origem que não existe, e
não há forma de tornar um `COPY` opcional.

Duas soluções possíveis: criar `public/.gitkeep` no repositório da aplicação
(foi o que se fez na altura), ou garantir a pasta na própria etapa de build. O
Dockerfile passou a fazer `RUN mkdir -p /app/public` depois do `npm run build`,
que resolve o caso sem impor nada ao repositório da aplicação.
