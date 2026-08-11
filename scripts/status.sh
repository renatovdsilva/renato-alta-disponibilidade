#!/usr/bin/env bash
# Panorâmica rápida do cluster.
set -euo pipefail
echo "===== NÓS ====="
kubectl get nodes -o wide
echo; echo "===== PODS ====="
kubectl get pods -A -o wide
echo; echo "===== SERVIÇOS E INGRESS ====="
kubectl get svc,ingress -A
echo; echo "===== EVENTOS RECENTES ====="
kubectl get events -A --sort-by='.lastTimestamp' 2>/dev/null | tail -15
echo; echo "===== CONSUMO ====="
kubectl top nodes 2>/dev/null || echo "(metrics-server não disponível)"
