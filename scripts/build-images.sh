#!/usr/bin/env bash
# Constrói as imagens e importa-as para o cluster.
set -euo pipefail

CLUSTER="alta-disponibilidade"
QUINTA_SRC="${QUINTA_SRC:-$HOME/projects/quintadocalvario}"
BRIOSA_SRC="${BRIOSA_SRC:-$HOME/projects/briosatecnica-agenda}"
TAG="${1:-1.0.0}"

build() {
  local name="$1" src="$2" dockerfile="$3"
  if [ ! -d "$src" ]; then
    echo "!! $src não existe — define a variável de ambiente correspondente."
    return
  fi
  echo "==> A construir $name:$TAG"
  local start=$(date +%s)
  docker build -t "$name:$TAG" -f "$dockerfile" "$src"
  local end=$(date +%s)
  local size=$(docker image inspect "$name:$TAG" --format='{{.Size}}' | awk '{printf "%.1f MB", $1/1024/1024}')
  echo "    tamanho: $size | tempo: $((end-start))s"
  k3d image import "$name:$TAG" -c "$CLUSTER"
}

build quinta-calvario "$QUINTA_SRC" "$(pwd)/apps/quinta-calvario/Dockerfile"
build briosa-agenda   "$BRIOSA_SRC" "$(pwd)/apps/briosa-agenda/Dockerfile"

echo "==> Registar os números em docs/11-metricas.md"
