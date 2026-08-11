# 08 — Operação do dia a dia

## 8.1 Arranque

Depois de reiniciar o Windows:

```bash
k3d cluster start alta-disponibilidade
kubectl get nodes
```

---

## 8.2 Comandos de rotina

```bash
# estado geral
kubectl get pods -A
kubectl get nodes -o wide
kubectl top nodes            # requer metrics-server
kubectl top pods -A

# investigar um pod
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> -f
kubectl logs <pod> -n <ns> --previous     # logs do container anterior
kubectl exec -it <pod> -n <ns> -- sh

# eventos recentes (o primeiro sítio a olhar)
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# rede
kubectl get svc,ingress -A
kubectl port-forward svc/<svc> -n <ns> 8080:80
```

---

## 8.3 Publicar uma nova versão

```bash
# 1. construir
docker build -t quinta-calvario:1.1.0 apps/quinta-calvario

# 2. importar para o cluster
k3d image import quinta-calvario:1.1.0 -c alta-disponibilidade

# 3. atualizar a tag no values e fazer commit
#    o ArgoCD trata do resto

# 4. acompanhar
kubectl rollout status deployment/quinta-web -n quinta
```

---

## 8.4 Backup do que interessa

O cluster é descartável — o que não pode perder-se é este repositório e os dados persistentes.

```bash
# exportar todos os manifests aplicados
kubectl get all -A -o yaml > backup/cluster-$(date +%F).yaml
```

---

## 8.5 Recomeçar do zero

```bash
k3d cluster delete alta-disponibilidade
./scripts/bootstrap.sh
```

Se o bootstrap reconstrói tudo sem intervenção manual, a automação está correta. **Este é o teste real do projeto.**
