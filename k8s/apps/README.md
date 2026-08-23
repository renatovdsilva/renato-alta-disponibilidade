# `k8s/apps/` — manifests das aplicações geridas por GitOps

Uma pasta por aplicação. Cada uma é a fonte de verdade de uma Application do
ArgoCD em `argocd/`.

```
k8s/apps/
├── renatotrack/     → Application "renatotrack"  → namespace renatotrack
└── fitness/         → Application "fitness"      → namespace fitness
```

---

## Porquê aqui, e não noutro sítio

O repositório já tinha duas pastas que podiam parecer candidatas. Nenhuma
servia:

| Pasta | Para que é | Porque não serve |
|---|---|---|
| `apps/` | Dockerfiles, `.dockerignore` e notas de build | é sobre **construir imagens**, não sobre correr no cluster. Misturar as duas coisas com o mesmo nome era garantir confusão |
| `k8s/base/` | manifests da Quinta e da Briosa, aplicados com `kubectl` | é a montagem pré-GitOps. A Quinta já lá não é aplicada — passou para o chart |
| `charts/` | Helm charts | ver abaixo |

`k8s/apps/<nome>/` mantém a coerência com o resto da árvore `k8s/` (`base`,
`overlays`, `platform`) e deixa claro, só pelo caminho, que cada subpasta é uma
unidade de deploy independente.

## Porquê manifests simples e não Helm charts

A Quinta usa um chart porque precisa de valores diferentes por ambiente
(`values-dev.yaml`, `values-prod.yaml`). Estas duas aplicações têm um ambiente
só.

Converter agora daria trabalho e nenhum benefício: os manifests já existem,
já foram testados no cluster, e o ArgoCD lê YAML simples tão bem como charts.
Quando uma delas precisar de um segundo ambiente, converte-se nessa altura —
com o problema concreto à frente, em vez de o adivinhar.

O ArgoCD suporta os dois formatos em simultâneo, sem configuração especial.

---

## Regra que não muda

**Nenhum Secret com valores reais entra aqui.** Os Secrets são criados à mão no
cluster e a sua existência fica documentada como pré-requisito em
`docs/13-aplicacoes-gitops.md`. Exemplos com placeholders vivem em
`k8s/examples/`.

Se um Secret com valores reais for commitado, considera-se comprometido a
partir desse instante — rodar a credencial não o apaga do histórico.
