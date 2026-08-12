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

## 8.5 Recuperação de queda de energia — caso real

**12/08/2026, ~07:41 UTC.** Falha de energia sem encerramento ordenado, com o
cluster a correr e o ArgoCD já sincronizado. A máquina é um desktop, sem
bateria — a queda foi à bruta.

Não foi um teste. É o cenário que se tenta simular com `kill -9` e nunca sai
igual.

### O que aconteceu sem ninguém tocar em nada

| Camada | Comportamento |
|---|---|
| Docker Desktop | arrancou com o sistema |
| Contentores do k3d | os 4 voltaram sozinhos (`serverlb`, `server-0`, `agent-0`, `agent-1`) |
| k3s / control plane | recuperou o estado a partir do disco |
| PVC do Postgres | remontado com o **mesmo identificador**, dados intactos |
| Flannel | reciclou as regras de iptables, reescreveu `/run/flannel/subnet.env` e restabeleceu os túneis vxlan entre `172.18.0.3` e `172.18.0.4` |
| Network policy controller | v2.6.3-k3s1 reiniciou sem problemas |
| Pods | todos `Running`, em todos os namespaces |

**Recuperação completa em ~5 minutos, com zero intervenção manual.** Nem sequer
foi preciso `k3d cluster start` — o passo que a secção 8.1 dá como necessário
depois de reiniciar o Windows só se aplica quando o Docker Desktop **não**
arranca automaticamente.

Volume remontado:

```
MountVolume.MountDevice succeeded for volume pvc-27b2a2b2-7214-4a47-865f-eaedc9a6fc5a
/var/lib/rancher/k3s/storage/pvc-27b2a2b2-..._quinta_data-postgres-0
```

O mesmo `pvc-` de antes da queda. É a prova de que o `local-path` do k3s
escreve em disco no nó e sobrevive à destruição do contentor — o que também
significa, do lado mau, que os dados estão presos àquele nó.

### Mensagens de arranque que parecem erros e não são

| Mensagem | Significado |
|---|---|
| `no subnet found for key: FLANNEL_NETWORK` | normal durante o arranque, antes de o flannel reescrever `subnet.env` |
| `prober_manager.go: Failed to trigger a manual run probe=Readiness` | transitório, enquanto o kubelet ainda está a registar os pods |
| pods em `Unknown` | o control plane perdeu contacto com o kubelet do nó; ver `docs/09-troubleshooting.md` |

### O que não recuperou

Todos os `kubectl port-forward` morreram com a queda — o do ArgoCD na 8081 e o
do Ingress na 8080. É a mesma lição da secção 4.6 do doc 04, agora com um
segundo exemplo: **o cluster recupera sozinho, os túneis de desenvolvimento
não.** São processos na máquina, não recursos do Kubernetes, e ninguém os
repõe.

```bash
# repor depois de uma queda
kubectl port-forward svc/argocd-server -n argocd 8081:443 &
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80 &
```

### O que isto vale

Um cluster de laboratório sobreviveu a um corte de energia sem encerramento
ordenado, recuperou sozinho em cinco minutos e não perdeu dados. Nenhum teste
simulado dá esta garantia — e é por isso que fica documentado com data e hora.

---

## 8.6 Recomeçar do zero

```bash
k3d cluster delete alta-disponibilidade
./scripts/bootstrap.sh
```

Se o bootstrap reconstrói tudo sem intervenção manual, a automação está correta. **Este é o teste real do projeto.**
