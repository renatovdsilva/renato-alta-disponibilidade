#!/usr/bin/env bash
# Gera k8s/base/32-mysql-schema-configmap.yaml a partir do schema.sql
# que vive no repositório da aplicação.
#
# O schema NÃO é duplicado neste repositório de propósito: a fonte de verdade
# é a aplicação. Este script transforma-o em ConfigMap, que o StatefulSet monta
# em /docker-entrypoint-initdb.d e o MySQL corre na primeira inicialização.
#
# Correr sempre que o schema mudar, e voltar a commitar o ficheiro gerado.
set -euo pipefail

APP_REPO="${APP_REPO:-$HOME/projects/briosatecnica-agenda}"
SCHEMA="${APP_REPO}/public_html/public_html/app/database/schema.sql"
OUT="$(cd "$(dirname "$0")/.." && pwd)/k8s/base/32-mysql-schema-configmap.yaml"

[ -f "$SCHEMA" ] || {
  echo "xx  schema.sql não encontrado em: $SCHEMA"
  echo "    Define APP_REPO se o repositório estiver noutro sítio."
  exit 1
}

echo "==> A gerar ConfigMap a partir de $SCHEMA"

{
  echo "# GERADO POR scripts/gen-mysql-schema.sh — NÃO EDITAR À MÃO."
  echo "# Fonte: briosatecnica-agenda/public_html/public_html/app/database/schema.sql"
  echo "# Regenerar com: ./scripts/gen-mysql-schema.sh"
  kubectl create configmap mysql-schema \
    --namespace briosa \
    --from-file=schema.sql="$SCHEMA" \
    --dry-run=client -o yaml
} > "$OUT"

echo "==> Escrito: $OUT"
echo
echo "Confirma antes de aplicar:"
echo "  - o nome da base de dados no schema tem de ser o mesmo do Secret (DB_NAME)"
echo "  - CHARACTER SET utf8mb4 nas tabelas"
grep -iE "create database|character set|collate" "$SCHEMA" | head -10 || true
