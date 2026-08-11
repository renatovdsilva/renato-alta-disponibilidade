# Quinta do Calvário — notas de build

Next.js 14 + TypeScript + Prisma + NextAuth.

Repositório: `github.com/renatovdsilva/quintadocalvario`

---

## Estado do repositório

Levantado em 11/08/2026.

```
quintadocalvario/
├── app/                components/       lib/
├── prisma/             schema.prisma, seed.ts
├── middleware.ts       next.config.mjs   package.json    tsconfig.json
├── instalar.bat        push-github.bat   ← scripts de Windows, fora da imagem
└── (sem package-lock.json)               ← tem de ser gerado
```

**Dependências:** Next `^14.2.0`, React `^18.3.0`, `@prisma/client` `^5.14.0`,
`next-auth` `^4.24.0`, `bcryptjs`, `date-fns`, `date-fns-tz`. Dev: TypeScript
`^5`, `prisma` `^5.14.0`, `ts-node`.

---

## Pendências antes do build

### 1. Não existe `package-lock.json`

O `npm ci` — que é o que o Dockerfile usa — exige lockfile e falha sem ele.
E é precisamente por isso que se usa `npm ci` e não `npm install`: o lockfile
fixa as versões exatas, e sem ele duas imagens construídas com uma semana de
intervalo podem levar dependências diferentes. Gerar e commitar:

```bash
cd ~/projects/quintadocalvario
npm install                 # gera o package-lock.json
git add package-lock.json && git commit -m "Adiciona package-lock.json"
```

### 2. Datasource do Prisma

Era `sqlite` com `file:./dev.db`. Passa a PostgreSQL — decisão D9 em
`docs/10-decisoes.md`:

```prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}
```

A `url` nunca é escrita no ficheiro. Vem de `DATABASE_URL`, que no cluster é
injetada a partir do Secret `quinta-db`.

### 3. `output: 'standalone'` — e o ficheiro tem de ser `.mjs`

Configuração em TypeScript só é suportada a partir do **Next 15**. Neste
projeto (Next 14.2) o `next.config.ts` era simplesmente ignorado: o
`output: 'standalone'` nunca se aplicava, o `.next/standalone` não era gerado e
a etapa de runtime do Dockerfile ficava sem o que copiar.

Convertido para `next.config.mjs` em 11/08/2026:

```js
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  eslint:     { ignoreDuringBuilds: true },
  typescript: { ignoreBuildErrors: true },
};
export default nextConfig;
```

### 4. Variáveis do NextAuth

Sem `NEXTAUTH_SECRET` o NextAuth devolve 500 em `/api/auth/error` com o erro
`NO_SECRET`. Em desenvolvimento ficam em `.env.local` — **que tem de estar no
`.gitignore`**:

```bash
echo "NEXTAUTH_SECRET=$(openssl rand -base64 32)" >> .env.local
echo "NEXTAUTH_URL=http://localhost:3002"         >> .env.local
echo ".env.local" >> .gitignore
```

No cluster vêm do Secret `quinta-db`, e o `NEXTAUTH_URL` passa a ser o host do
Ingress (`http://quinta.localhost`), não o localhost de desenvolvimento — o
NextAuth usa este valor para construir os URLs de callback, por isso um valor
errado parte o login em produção mesmo com o secret correto.

---

## Primeiro arranque — 11/08/2026

Primeira execução da aplicação, alguma vez. Confirmado:

| Item | Resultado |
|---|---|
| Next.js | 14.2.35, *Ready* em 2.1 s |
| Prisma Client | v5.22.0 gerado |
| Base de dados | `prisma db push` criou a base (SQLite, ainda) |
| Seed | criou `admin@quintacalvario.pt` |
| Autenticação | login com sucesso |
| Dashboard | renderiza — 5 quartos, secções Calendário, Reservas e Quartos |

Ou seja, a aplicação está funcional antes de entrar no cluster. O que falhar a
partir daqui é da containerização ou do Kubernetes, não do código — e isso
poupa muito tempo de diagnóstico.

---

## Dívida técnica

O `next.config.mjs` mantém:

```ts
eslint:     { ignoreDuringBuilds: true }
typescript: { ignoreBuildErrors: true }
```

O build passa mesmo com erros de tipos ou de lint. Fica assim para desbloquear
a containerização, mas é o primeiro candidato a corrigir quando houver
pipeline de CI — caso contrário publica-se uma imagem com código que não
compila em condições, e a falha só aparece em runtime. Registado como DT1 em
`docs/10-decisoes.md`.

---

## Build

Baseline **primeiro**, antes de existir `.dockerignore`:

```bash
cd ~/projects/quintadocalvario
REPO=~/Documents/renato-alta-disponibilidade

cp $REPO/apps/quinta-calvario/Dockerfile.baseline .
time docker build -f Dockerfile.baseline -t quinta-calvario:baseline .

cp $REPO/apps/quinta-calvario/Dockerfile .
cp $REPO/apps/quinta-calvario/.dockerignore .
time docker build -t quinta-calvario:1.0.0 .

docker images | grep quinta-calvario
```

A diferença entre as duas é o número legítimo para o currículo: multi-stage a
sério, com separação entre compilação e execução.

Testar (precisa de uma `DATABASE_URL` alcançável):

```bash
docker run --rm -p 3000:3000 -e DATABASE_URL="postgresql://..." quinta-calvario:1.0.0
```

Importar para o cluster:

```bash
k3d image import quinta-calvario:1.0.0 -c alta-disponibilidade
```

---

## Porta

O container corre sempre na **3000** (`ENV PORT=3000`), apesar de os scripts
`dev` e `start` do `package.json` usarem a 3002. A porta de desenvolvimento
não tem efeito dentro do container, e a 3000 é a que já está nos manifests, no
chart e no Service. O container corre como `nextjs` (uid 1001), não como root.
