# Briosa Agenda — notas de build

Aplicação PHP (MVC feito à mão, sem Composer) servida por Apache, com MySQL.

Repositório: `github.com/renatovdsilva/briosatecnica-agenda`

---

## Estrutura real do repositório

Levantada em 11/08/2026. **O código está aninhado dois níveis** — é o erro
mais fácil de cometer a escrever o Dockerfile.

```
briosatecnica-agenda/
├── public_html.zip            ← duplicado do código, não entra na imagem
└── public_html/
    └── public_html/           ← DOCUMENT ROOT real
        ├── index.php
        ├── gera_senha.php     ← utilitário, não deve ser servido
        ├── error_log          ← commitado por engano
        ├── views/
        └── app/
            ├── index.php
            ├── error_log
            ├── README.md
            ├── config/
            │   ├── app.php
            │   └── database.php    ← CREDENCIAIS EM TEXTO LIMPO
            ├── database/
            │   └── schema.sql
            ├── src/
            │   ├── Controllers/    Agenda, Auth, Dashboard
            │   ├── Core/           Auth, Csrf, Database, View, helpers
            │   └── Models/         User
            ├── templates/
            └── views/
```

Portanto, no Dockerfile:

```dockerfile
COPY --chown=www-data:www-data public_html/public_html/ /var/www/html/
```

---

## Base de dados

MySQL. O `app/config/database.php` devolve um array com `127.0.0.1:3306` e
charset `utf8`. A extensão necessária é **`pdo_mysql`**.

No cluster, o MySQL corre como StatefulSet no namespace `briosa` — decisão D8
em `docs/10-decisoes.md`. Os manifests estão em `k8s/base/30..32-mysql-*.yaml`.

---

## Problemas conhecidos

Levantados em 11/08/2026. Os dois primeiros têm de estar resolvidos antes de
qualquer deploy.

### 1. Credenciais em texto limpo num repositório público — CRÍTICO

`app/config/database.php` tem a password da base de dados em claro, e o
repositório é público.

- [ ] Rodar a credencial (a exposta deve ser considerada comprometida)
- [ ] Retirar o ficheiro do repositório e acrescentá-lo ao `.gitignore`
- [ ] Passar a ler de variáveis de ambiente vindas de um Secret

Rodar a password não chega: enquanto o ficheiro estiver no histórico do Git,
a password antiga continua visível em commits anteriores. Reescrever o
histórico é o passo seguinte, mas só depois da credencial estar trocada.

Forma pretendida do `database.php`:

```php
<?php
return [
    'host'    => getenv('DB_HOST')    ?: '127.0.0.1',
    'port'    => getenv('DB_PORT')    ?: '3306',
    'name'    => getenv('DB_NAME')    ?: 'agenda_briosa',
    'user'    => getenv('DB_USER')    ?: 'briosa',
    'pass'    => getenv('DB_PASSWORD') ?: '',
    'charset' => getenv('DB_CHARSET') ?: 'utf8mb4',
];
```

Sem valores reais como fallback — se a variável faltar, é preferível falhar.

### 2. Nome da base de dados divergente

| Sítio | Nome |
|---|---|
| `app/config/database.php` | `briosate_agenda` |
| `app/database/schema.sql` | `agenda_briosa` |

Escolhido **`agenda_briosa`**, o que o schema cria. O `DB_NAME` do Secret já
usa esse valor; falta corrigir o config da aplicação.

### 3. Ficheiros que não devem entrar na imagem

`public_html.zip`, os `error_log` commitados e o `gera_senha.php`. Tratados
pelo `.dockerignore` deste diretório — copiar para a raiz do repositório da
aplicação.

### 4. Charset inconsistente

Config em `utf8`, schema em `utf8mb4`. O `utf8` do MySQL são três bytes e não
cobre emojis nem alguns carateres. Deve ser `utf8mb4` nos dois — o servidor já
arranca com esse valor por omissão nos `args` do StatefulSet.

### 5. `app/` dentro do document root

Configuração, schema e código-fonte ficam alcançáveis por HTTP. O Dockerfile
bloqueia `app/config`, `app/database`, `error_log` e as extensões `.sql`,
`.md`, `.log`, `.zip` e `.ini` ao nível do Apache. É um remendo: a correção
verdadeira é mover `app/` para fora do document root e deixar lá só o
`index.php`. Fica registado para a aplicação, não para a infraestrutura.

---

## Build

Ordem obrigatória: **primeiro a baseline, depois o `.dockerignore`**. Se o
`.dockerignore` já existir, a imagem de comparação sai mais pequena e o número
da redução deixa de significar nada.

```bash
cd ~/projects/briosatecnica-agenda

# 1) baseline — antes de existir .dockerignore
cp ~/Documents/renato-alta-disponibilidade/apps/briosa-agenda/Dockerfile.baseline .
docker build -f Dockerfile.baseline -t briosa-agenda:baseline .

# 2) versão corrigida
cp ~/Documents/renato-alta-disponibilidade/apps/briosa-agenda/Dockerfile .
cp ~/Documents/renato-alta-disponibilidade/apps/briosa-agenda/.dockerignore .
docker build -t briosa-agenda:1.0.0 .

# 3) comparar — os números vão para docs/11-metricas.md
docker images | grep briosa-agenda
```

Testar antes de fazer deploy (sem base de dados, deve responder pelo menos
com a página de login ou um erro de ligação — não um 500 do Apache):

```bash
docker run --rm -p 8081:8080 briosa-agenda:1.0.0
# http://localhost:8081
```

Importar para o cluster:

```bash
k3d image import briosa-agenda:1.0.0 -c alta-disponibilidade
```

---

## Nota sobre a porta

O container corre como `www-data` e por isso o Apache escuta na **8080**, não
na 80 — um processo não-root não se pode ligar a portas abaixo de 1024. O
`containerPort` no Deployment é 8080; o Service continua a expor a 80 porque
aponta ao `targetPort` nomeado `http`.
