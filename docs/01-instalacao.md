# 01 — Instalação do ambiente

**Host:** Windows 11
**Objetivo:** ter WSL2, Docker e as ferramentas de linha de comandos prontas.

---

## 1.1 Requisitos

| Item | Mínimo | Recomendado |
|---|---|---|
| RAM | 8 GB | 16 GB |
| Disco livre | 40 GB | 60 GB |
| Windows | 10 v2004 | 11 |
| Virtualização | ativada na BIOS | — |

Confirmar virtualização: Gestor de Tarefas → Desempenho → CPU → "Virtualização: Ativado".

---

## 1.2 WSL2

No **PowerShell como Administrador**:

```powershell
wsl --install -d Ubuntu-22.04
```

Reiniciar. No primeiro arranque do Ubuntu, criar utilizador e password.

Verificar:

```powershell
wsl -l -v
```

Esperado: `Ubuntu-22.04   Running   2`. Se a versão for 1:

```powershell
wsl --set-version Ubuntu-22.04 2
```

### Limitar recursos do WSL (opcional, recomendado com 8 GB)

Criar `C:\Users\<utilizador>\.wslconfig`:

```ini
[wsl2]
memory=6GB
processors=4
swap=2GB
```

Aplicar com `wsl --shutdown` e voltar a abrir.

---

## 1.3 Docker Desktop

1. Instalar a partir de docker.com
2. Settings → General → **Use the WSL 2 based engine** ✔
3. Settings → Resources → WSL Integration → ativar `Ubuntu-22.04` ✔

Verificar dentro do Ubuntu:

```bash
docker version
docker run --rm hello-world
```

---

## 1.4 Ferramentas de linha de comandos

Tudo dentro do Ubuntu (WSL).

```bash
sudo apt update && sudo apt install -y curl git make jq

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Verificação final:

```bash
kubectl version --client && k3d version && helm version && docker version
```

---

## 1.5 Node.js dentro do Ubuntu — armadilha do interop

Necessário para construir a Quinta do Calvário. **Instalar o Node dentro do
Ubuntu, mesmo que `node -v` já responda.** Se responder sem estar instalado no
Linux, está a responder o Node do *Windows*.

O WSL2 acrescenta o `PATH` do Windows ao `PATH` do Linux (funcionalidade
chamada *interop*). Isso é conveniente para chamar `explorer.exe`, mas faz com
que `node` e `npm` resolvam para os executáveis do Windows quando não existe
versão Linux instalada. O comando corre, imprime uma versão — e depois os
scripts do npm falham:

```
UNC paths are not supported. Defaulting to Windows directory.
```

O `npm` do Windows tenta usar o `CMD.EXE` para correr os scripts, e o CMD não
sabe lidar com o caminho `\\wsl.localhost\...` do sistema de ficheiros Linux.
O erro não diz nada sobre Node nem sobre WSL, o que o torna difícil de
diagnosticar.

**Diagnóstico:**

```bash
which node npm
```

Se aparecer `/mnt/c/Program Files/nodejs/node`, é o Node do Windows. O que se
quer é `/usr/bin/node` e `/usr/bin/npm`.

**Instalação (NodeSource, Node 20 LTS):**

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

which node npm && node -v && npm -v
```

O Node 20 é o mesmo da imagem base do Dockerfile da Quinta (`node:20-alpine`) —
o que se constrói localmente corre no mesmo runtime que vai para o cluster.

> Alternativa: desligar o interop em `/etc/wsl.conf` com
> `[interop] appendWindowsPath = false`. Resolve o sintoma, mas tira o acesso a
> todos os executáveis do Windows a partir do Ubuntu. Instalar o Node no Linux
> é a solução, não o contorno.

---

## 1.6 Atalhos úteis no shell

Acrescentar ao `~/.bashrc`:

```bash
alias k='kubectl'
alias kgp='kubectl get pods -A'
alias kgn='kubectl get nodes -o wide'
source <(kubectl completion bash)
complete -F __start_kubectl k
```

---

## Registo

**Versões instaladas em 10/08/2026:**

| Ferramenta | Versão |
|---|---|
| Docker | 29.7.2 (API 1.55) |
| Docker Desktop | 4.86.0 |
| kubectl | v1.36.3 (Kustomize v5.8.1) |
| k3d | v5.9.0 |
| k3s (por omissão no k3d) | v1.35.5-k3s1 |
| Helm | v3.21.3 |
| Node.js (Ubuntu, NodeSource) | v20.20.2 — instalado em 11/08/2026 |
| npm | `/usr/bin/npm` |

| Data | O que foi feito | Notas |
|---|---|---|
| 10/08/2026 | WSL2 + Ubuntu 22.04 | ver `01-instalacao-wsl2.md` |
| 10/08/2026 | Docker Desktop instalado e integrado | dois erros pelo caminho, documentados |
| 10/08/2026 | kubectl, k3d e Helm instalados | sem problemas |
| 11/08/2026 | Node.js 20 instalado no Ubuntu | o `node -v` já respondia **v24.14.1** — era o Node do *Windows* via interop. Ver 1.5 |

> A versão do k3s por omissão no k3d 5.9.0 é a **v1.35.5**. Relevante para o CKA, cujo exame usa a v1.35 — o laboratório está alinhado com a versão do exame.
