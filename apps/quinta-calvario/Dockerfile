# syntax=docker/dockerfile:1
#
# Quinta do Calvário — imagem de produção, multi-stage.
#
# Contexto de build: a raiz do repositório quintadocalvario.
#   cd ~/projects/quintadocalvario
#   docker build -t quinta-calvario:1.0.0 .
#
# Pré-requisitos no repositório da aplicação:
#   - next.config.mjs com output: 'standalone'  (feito — .ts só a partir do Next 15)
#   - package-lock.json commitado               (npm ci não corre sem ele)
#   - schema.prisma com provider = "postgresql" e url = env("DATABASE_URL")
#
# Variáveis exigidas em runtime, injetadas a partir do Secret quinta-db:
#   DATABASE_URL, NEXTAUTH_SECRET, NEXTAUTH_URL

# ---------- 1. dependências ----------
# Etapa separada para o cache: só volta a correr se package*.json mudarem.
FROM node:20-alpine AS deps
WORKDIR /app
RUN apk add --no-cache libc6-compat openssl
COPY package.json package-lock.json ./
RUN npm ci

# ---------- 2. build ----------
FROM node:20-alpine AS builder
WORKDIR /app
RUN apk add --no-cache libc6-compat openssl
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# prisma generate ANTES do build: o Next compila código que importa
# @prisma/client, e o cliente só existe depois de gerado.
RUN npx prisma generate
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build
# A Quinta não tem pasta public/. O COPY da etapa seguinte falharia com
# "not found" — o Docker não permite copiar uma origem inexistente, e não há
# forma de o tornar opcional. Criar aqui garante que existe sempre, mesmo que
# vazia, sem obrigar o repositório da aplicação a ter um .gitkeep.
RUN mkdir -p /app/public

# ---------- 3. runtime ----------
# Aqui está o ganho do multi-stage: esta imagem não leva node_modules
# completo, nem código-fonte, nem toolchain de compilação. Leva o bundle
# standalone, que já traz só as dependências que o servidor usa.
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

# openssl é preciso em runtime para o Prisma; wget vem no busybox do alpine
# e serve o HEALTHCHECK sem instalar curl.
RUN apk add --no-cache openssl \
 && addgroup -g 1001 nodejs \
 && adduser -S -u 1001 -G nodejs nextjs

COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
# schema.prisma e migrações: o cliente gerado precisa do schema em runtime,
# e tê-lo na imagem permite correr `prisma migrate deploy` a partir dela.
COPY --from=builder --chown=nextjs:nodejs /app/prisma ./prisma
COPY --from=builder --chown=nextjs:nodejs /app/node_modules/.prisma ./node_modules/.prisma

USER nextjs
EXPOSE 3000

# PORT=3000 fixo, apesar de o script `start` do package.json usar a 3002:
# a porta de desenvolvimento é irrelevante dentro do container, e 3000 é o
# que já está nos manifests, no chart e no Service.
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s \
  CMD wget -qO- http://127.0.0.1:3000/ >/dev/null || exit 1

CMD ["node", "server.js"]
