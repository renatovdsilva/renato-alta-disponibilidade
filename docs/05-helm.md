# 05 — Helm

## 5.1 Porquê passar de YAML para chart

Com ficheiros YAML soltos, cada ambiente exige uma cópia do ficheiro. Com Helm, existe um único template e valores diferentes por ambiente.

| Sem Helm | Com Helm |
|---|---|
| ficheiros duplicados por ambiente | um template, vários `values` |
| versão não controlada | `helm history` e `helm rollback` |
| instalar e remover à mão | `helm install` / `helm uninstall` |

---

## 5.2 Estrutura

```
charts/quinta/
├── Chart.yaml
├── values.yaml            # valores por defeito
├── values-dev.yaml        # 1 réplica, recursos baixos
├── values-prod.yaml       # 2 réplicas, recursos maiores
└── templates/
    ├── namespace.yaml
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    └── _helpers.tpl
```

---

## 5.3 Comandos

```bash
# validar sem aplicar
helm template quinta ./charts/quinta

# ver o que muda antes de aplicar
helm diff upgrade quinta ./charts/quinta   # requer plugin helm-diff

# instalar ou atualizar
helm upgrade --install quinta ./charts/quinta \
  -n quinta --create-namespace \
  -f charts/quinta/values-prod.yaml

# histórico e rollback
helm history quinta -n quinta
helm rollback quinta 1 -n quinta

# remover
helm uninstall quinta -n quinta
```

---

## 5.4 Boas práticas seguidas

- Nada de valores fixos nos templates — tudo vem de `values.yaml`.
- `_helpers.tpl` para nomes e labels, evitando repetição.
- Labels padrão do Kubernetes (`app.kubernetes.io/name`, `app.kubernetes.io/instance`).
- `helm template` corrido sempre antes de aplicar, para apanhar erros de sintaxe.

---

## Registo

| Data | Chart | Versão | Ambiente |
|---|---|---|---|
| | quinta | 0.1.0 | |
