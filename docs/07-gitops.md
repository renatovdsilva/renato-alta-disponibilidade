# 07 — GitOps com ArgoCD

## 7.1 O que muda

Sem GitOps, o estado do cluster vive na cabeça de quem correu o último `kubectl apply`.
Com GitOps, o estado desejado está no Git e o ArgoCD encarrega-se de o fazer coincidir com a realidade.

| Antes | Depois |
|---|---|
| `kubectl apply` manual | commit no Git |
| sem histórico de quem alterou | histórico completo no Git |
| drift silencioso | ArgoCD deteta e corrige |
| rollback = lembrar-se do estado anterior | rollback = `git revert` |

---

## 7.2 Instalação

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available deployment --all -n argocd --timeout=300s
```

Password inicial:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

Aceder:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

`https://localhost:8080` — utilizador `admin`.

> Mudar a password e apagar o secret inicial:
> ```bash
> kubectl -n argocd delete secret argocd-initial-admin-secret
> ```

---

## 7.3 Application

Ficheiro: [`argocd/quinta-application.yaml`](https://github.com/renatovdsilva/renato-alta-disponibilidade/blob/main/argocd/quinta-application.yaml)

```bash
kubectl apply -f argocd/
```

Pontos importantes da definição:

- `syncPolicy.automated.prune: true` — apagar do Git apaga do cluster
- `selfHeal: true` — alterações manuais no cluster são revertidas
- `CreateNamespace=true` — o namespace é criado se não existir

---

## 7.4 Fluxo de trabalho a partir daqui

```
alterar values.yaml → git commit → git push → ArgoCD sincroniza → cluster atualizado
```

Nunca mais `kubectl apply` em produção. Se for preciso alterar alguma coisa, altera-se no Git.

---

## 7.5 Demonstração de self-heal

```bash
kubectl scale deployment quinta-web -n quinta --replicas=5
# esperar ~1 minuto
kubectl get pods -n quinta
```

O ArgoCD repõe o valor definido no Git. **Registar o tempo até à correção.**

---

## Registo

| Data | Ação | Observação |
|---|---|---|
| | ArgoCD instalado | |
| | self-heal testado | tempo: |
