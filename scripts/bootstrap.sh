#!/usr/bin/env bash
# Cria o cluster de raiz e instala tudo. Idempotente.
set -euo pipefail

CLUSTER="alta-disponibilidade"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}!! ${NC} $*"; }
die()  { echo -e "${RED}xx ${NC} $*"; exit 1; }

log "A verificar dependências"
for cmd in docker kubectl k3d helm; do
  command -v "$cmd" >/dev/null || die "$cmd não encontrado. Ver docs/01b-instalacao-ferramentas.md"
done
docker info >/dev/null 2>&1 || die "Docker não está a correr. Abre o Docker Desktop."

if k3d cluster list | grep -q "^${CLUSTER}"; then
  warn "Cluster '${CLUSTER}' já existe. A ignorar a criação."
else
  log "A criar o cluster ${CLUSTER} (1 server + 2 agents)"
  k3d cluster create "${CLUSTER}" \
    --servers 1 \
    --agents 2 \
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0" \
    --wait
fi

log "A aguardar que os nós fiquem Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=180s

log "A instalar o Ingress NGINX"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --wait --timeout 5m

log "A criar namespaces"
kubectl apply -f k8s/base/00-namespaces.yaml

log "A importar imagens para o cluster (se existirem localmente)"
for img in quinta-calvario:1.0.0 briosa-agenda:1.0.0; do
  if docker image inspect "$img" >/dev/null 2>&1; then
    k3d image import "$img" -c "${CLUSTER}"
  else
    warn "Imagem $img ainda não construída — ver docs/03-containerizacao.md"
  fi
done

log "A aplicar os manifests"
kubectl apply -f k8s/base/

log "Estado do cluster"
kubectl get nodes -o wide
kubectl get pods -A

echo
log "Cluster pronto."
echo "  Aplicações:  http://quinta.localhost   http://briosa.localhost"
echo "  Passos seguintes: docs/06-monitorizacao.md e docs/07-gitops.md"
