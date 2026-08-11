# 02 — Criação do cluster

## 2.1 Porquê k3d e não minikube ou kind

| Opção | Nós múltiplos | RAM | Notas |
|---|---|---|---|
| **k3d (k3s em Docker)** | sim, trivial | baixa | escolhido |
| kind | sim | média | mais lento a arrancar |
| minikube | um nó por defeito | alta | mais pesado |
| Docker Desktop K8s | um nó | alta | sem controlo do control plane |

O k3s é uma distribuição Kubernetes certificada pela CNCF. A API é a mesma — o que se aprende aqui aplica-se a qualquer cluster.

---

## 2.2 Criar o cluster

```bash
k3d cluster create alta-disponibilidade \
  --servers 1 \
  --agents 2 \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0"
```

| Argumento | Razão |
|---|---|
| `--servers 1` | um control plane |
| `--agents 2` | dois workers, para ver scheduling e tolerância a falhas |
| `--port 80/443` | expõe o ingress ao browser do Windows |
| `--disable=traefik` | vamos usar Ingress NGINX, que é o que aparece nas vagas |

---

## 2.3 Verificação

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

Os três nós devem estar `Ready`.

---

## 2.4 Ciclo de vida

```bash
k3d cluster stop alta-disponibilidade    # desligar sem perder estado
k3d cluster start alta-disponibilidade   # voltar a ligar
k3d cluster delete alta-disponibilidade  # destruir
k3d cluster list                         # listar
```

> O cluster não arranca sozinho com o Windows. Depois de reiniciar o PC, correr `k3d cluster start`.

---

## 2.5 Ingress NGINX

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer

kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller
```

---

## Registo

**Cluster:** `alta-disponibilidade` · criado em 10/08/2026 · estado confirmado em 11/08/2026

Saída de `kubectl get nodes -o wide` em 11/08/2026:

| Nó | Papel | Estado | Idade | IP interno | Versão |
|---|---|---|---|---|---|
| k3d-alta-disponibilidade-server-0 | control-plane | Ready | 13h | 172.18.0.3 | v1.35.5+k3s1 |
| k3d-alta-disponibilidade-agent-0 | worker | Ready | 13h | 172.18.0.4 | v1.35.5+k3s1 |
| k3d-alta-disponibilidade-agent-1 | worker | Ready | 13h | 172.18.0.5 | v1.35.5+k3s1 |

**Imagem do SO dos nós:** K3s v1.35.5+k3s1
**Runtime de contentores:** containerd 2.2.3-k3s1
**Kernel:** 6.18.33.2-microsoft-standard-WSL2

| Data | Ação | Resultado |
|---|---|---|
| 10/08/2026 | `k3d cluster create` | **ok** — 3 nós `Ready` em ~75 s |
| 11/08/2026 | verificação do estado | **ok** — os 3 nós continuam `Ready` com 13 h de uptime, sem recriar o cluster |
| 11/08/2026 | ingress instalado | **ok** — controller `Running` (1/1) em ~76 s, sem restarts |

**Ingress NGINX** · instalado em 11/08/2026, 07:06:51

Comando usado (variante idempotente do `scripts/bootstrap.sh`):

```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --wait --timeout 5m
```

| Item | Valor |
|---|---|
| Release Helm | `ingress-nginx` · namespace `ingress-nginx` · revisão 1 · `deployed` |
| Pod do controller | `ingress-nginx-controller-6c7cd85885-gpj5f` · `1/1 Running` · 0 restarts |
| Tempo até ficar pronto | ~76 s |
| Service | `ingress-nginx-controller` · tipo `LoadBalancer` · ClusterIP `10.43.249.155` |
| EXTERNAL-IP | `172.18.0.3`, `172.18.0.4`, `172.18.0.5` (os três nós) |
| Portas | `80:32376/TCP`, `443:32609/TCP` |
| Admission webhook | `ingress-nginx-controller-admission` · `ClusterIP` `10.43.123.147` · 443/TCP |

### Observações

- Os três nós partilham o kernel do WSL2 (`6.18.33.2-microsoft-standard-WSL2`), o que confirma que são contentores e não máquinas independentes. É a limitação assumida na decisão D1.
- A rede interna do cluster é a `172.18.0.0/16`, gerida pelo Docker.
- O runtime é o **containerd**, não o Docker — o k3s usa containerd diretamente. O Docker aqui serve apenas para criar os contentores que fazem de nós.
- O cluster aguentou 13 h ligado sem intervenção, incluindo o intervalo entre sessões. O `EXTERNAL-IP` dos nós aparece como `<none>`: é esperado, porque quem expõe o cluster ao Windows é o load balancer do k3d nas portas 80 e 443, não os nós.
- Em 11/08/2026 o namespace `ingress-nginx` ainda estava vazio — o cluster ficou de pé desde 10/08 mas o passo 2.5 não chegou a ser executado nessa sessão.
- O `EXTERNAL-IP` do service do ingress traz os IPs dos **três nós**, não um só. É o `servicelb` do k3s (klipper-lb): em vez de um balanceador externo, corre um DaemonSet que abre a porta em todos os nós e reencaminha para o Service. Daí um `LoadBalancer` num cluster local ter vários IPs — comportamento normal, não é erro de configuração.
- Os NodePorts `32376` (HTTP) e `32609` (HTTPS) são atribuídos automaticamente e mudam se o release for reinstalado. Não devem ser usados como endereço fixo: o acesso a partir do Windows faz-se pelas portas 80/443 mapeadas na criação do cluster.
- O `ingress-nginx-controller-admission` é um webhook de validação: rejeita objetos `Ingress` com sintaxe inválida no momento do `kubectl apply`, em vez de deixar o erro aparecer só depois no controller.
