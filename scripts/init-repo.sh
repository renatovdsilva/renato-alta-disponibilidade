#!/usr/bin/env bash
# Inicializa o repositório Git e publica no GitHub.
# Requer o GitHub CLI (gh) autenticado, ou faz o push manual no fim.
set -euo pipefail

REPO="renato-alta-disponibilidade"
USER="renatovdsilva"
DESC="Plataforma Kubernetes auto-hospedada — cluster k3s, Docker, Helm, ArgoCD, Prometheus e Grafana, com o processo todo documentado."

if [ ! -d .git ]; then
  git init -b main
fi

git add -A
git commit -m "Estrutura inicial: documentação, manifests, Helm chart, ArgoCD, alertas e scripts" || true

if command -v gh >/dev/null 2>&1; then
  echo "==> A criar o repositório no GitHub via gh"
  gh repo create "${USER}/${REPO}" --public --description "$DESC" --source=. --remote=origin --push
  echo
  echo "==> A ativar o GitHub Pages (documentação)"
  gh api -X POST "repos/${USER}/${REPO}/pages" -f build_type=workflow 2>/dev/null || \
    echo "   Ativar manualmente em Settings → Pages → Source: GitHub Actions"
else
  echo "!! GitHub CLI (gh) não encontrado."
  echo "   Cria o repositório em https://github.com/new com o nome ${REPO} e depois corre:"
  echo
  echo "   git remote add origin https://github.com/${USER}/${REPO}.git"
  echo "   git push -u origin main"
fi

echo
echo "Documentação ficará em: https://${USER}.github.io/${REPO}/"
