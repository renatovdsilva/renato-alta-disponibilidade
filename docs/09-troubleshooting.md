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

Criar `.wslconfig` (ver `docs/01-instalacao.md`) e correr `wsl --shutdown`.

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

Detalhe em `docs/01-instalacao.md`, secção 1.5.

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

## Registo pessoal

| Data | Problema | Causa | Solução | Tempo perdido |
|---|---|---|---|---|
| 11/08/2026 | Scripts npm falhavam com `UNC paths are not supported` | Node não estava instalado no Ubuntu; o interop do WSL resolvia `node`/`npm` para os binários do Windows (v24.14.1) | Node 20 LTS via NodeSource dentro do Ubuntu | |
| 11/08/2026 | `output: 'standalone'` não produzia efeito | `next.config.ts` não é suportado no Next 14, só a partir do 15 | Convertido para `next.config.mjs` | |
| 11/08/2026 | 500 em `/api/auth/error`, erro `NO_SECRET` | `NEXTAUTH_SECRET` e `NEXTAUTH_URL` não definidas | `.env.local` em desenvolvimento (no `.gitignore`), Secret no cluster | |
| 11/08/2026 | `prisma migrate dev` com P1017 | base de dados sombra força o fecho das ligações e mata o port-forward | `prisma db push`; `shadowDatabaseUrl` fica pendente | |
| 11/08/2026 | Build da Quinta falhava no `COPY /app/public` | a aplicação não tem pasta `public/` | `mkdir -p /app/public` na etapa de build | |
| 11/08/2026 | Aplicação com `E57P01` depois de recriar o `postgres-0` | pool com ligações mortas; port-forward preso ao pod antigo | reinício manual do port-forward e do servidor de dev | |
