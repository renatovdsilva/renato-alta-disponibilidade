# RenatoTrack — manifests para GitOps

Origem: `C:\Users\renat\Documents\RenatoTrack\deploy\k8s\`
Destino: esta pasta.

---

## O que copiar

| Ficheiro | Nota |
|---|---|
| Namespace `renatotrack` | pode ficar; o ArgoCD também o cria (`CreateNamespace=true`) |
| Deployment (2 réplicas) | confirmar `imagePullPolicy: IfNotPresent` — a imagem é local |
| Service | |
| Ingress (`track.localhost`) | |
| StatefulSet do PostgreSQL | |
| Service headless do PostgreSQL | |
| ConfigMaps, se existirem | desde que não tenham credenciais |

Sugestão de numeração, para a ordem de aplicação ser legível:

```
00-namespace.yaml
10-postgres-service.yaml
11-postgres-statefulset.yaml
20-deployment.yaml
21-service.yaml
22-ingress.yaml
```

## O que NÃO copiar

- **`Secret` `renatotrack-postgres`** — nem com os valores substituídos por
  placeholders. Fica em `k8s/examples/` e é criado à mão.
- Qualquer ficheiro `.env`, `kubeconfig` ou dump de base de dados.
- Ficheiros de backup ou `*-old.yaml`, `*.bak`, versões experimentais.
- O `PersistentVolumeClaim` **se** ele tiver sido criado pelo
  `volumeClaimTemplates` do StatefulSet — nesse caso já vem no StatefulSet, e
  tê-lo também à parte cria um conflito de propriedade.

## Antes de commitar

```bash
# 1) confirmar que não vai nenhum Secret
grep -ril "kind: Secret" k8s/apps/renatotrack/

# 2) confirmar que o que está no ficheiro é o que está no cluster
kubectl -n renatotrack get deploy,svc,ingress,statefulset -o yaml > /tmp/live.yaml
# comparar selectors, portas e nomes — divergências causam erro de sync
```

O ponto 2 é o que evita o problema que a Quinta teve: **o `spec.selector` de um
Deployment é imutável**. Se o do ficheiro não for idêntico ao que já está no
cluster, o primeiro sync falha com `field is immutable` e é preciso apagar e
recriar o Deployment.
