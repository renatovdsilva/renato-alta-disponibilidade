# 01a — Instalação do WSL2 (documentação do processo)

**Objetivo:** ter um Ubuntu 22.04 a correr sobre WSL2 no Windows, com Docker integrado, pronto a receber o cluster Kubernetes.

**Porquê WSL2 e não uma máquina virtual:** o WSL2 já corre um kernel Linux real numa VM leve gerida pelo Hyper-V. Uma VM tradicional acrescentaria uma segunda camada de virtualização, consumiria mais RAM e tornaria o Docker mais lento. Ver `docs/10-decisoes.md`, decisão D1.

---

## Passo 0 — Verificações prévias

### 0.1 Versão do Windows

```powershell
winver
```

Mínimo: Windows 10 versão 2004 (build 19041) ou Windows 11.
Se for inferior, atualizar o Windows antes de continuar.

### 0.2 Virtualização ativada

Gestor de Tarefas → **Desempenho** → **CPU** → procurar "Virtualização: **Ativado**".

Ou por linha de comandos:

```powershell
systeminfo | Select-String "Hyper-V"
```

Se estiver desativada, é preciso entrar na BIOS/UEFI e ativar:
- Intel → **Intel VT-x** (ou "Intel Virtualization Technology")
- AMD → **AMD-V** (ou "SVM Mode")

> Sem isto o WSL2 não arranca. É o bloqueio mais comum.

### 0.3 Espaço em disco

```powershell
Get-PSDrive C
```

Mínimo 40 GB livres. O WSL, as imagens Docker e os nós do cluster ocupam espaço rapidamente.

---

## Passo 1 — Instalar o WSL2

Abrir o **PowerShell como Administrador** (botão direito no menu Iniciar → Terminal (Admin)).

```powershell
wsl --install -d Ubuntu-22.04
```

Este comando faz tudo de uma vez: ativa as funcionalidades do Windows necessárias, instala o kernel Linux, define o WSL2 como versão predefinida e instala o Ubuntu.

**Reiniciar o computador.**

### Se o comando acima falhar

Fazer manualmente:

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

Reiniciar, depois instalar o pacote de atualização do kernel a partir de
`https://aka.ms/wsl2kernel`, e por fim:

```powershell
wsl --set-default-version 2
wsl --install -d Ubuntu-22.04
```

---

## Passo 2 — Primeiro arranque do Ubuntu

Ao reiniciar, abre-se uma janela do Ubuntu a pedir:

```
Enter new UNIX username:
New password:
Retype new password:
```

Escolher um utilizador em minúsculas, sem espaços. **Guardar a password** — é pedida em todos os `sudo`.

> A password não aparece enquanto se escreve. É normal.

---

## Passo 3 — Confirmar que está em WSL2

```powershell
wsl -l -v
```

Saída esperada:

```
  NAME            STATE           VERSION
* Ubuntu-22.04    Running         2
```

Se a coluna VERSION mostrar **1**:

```powershell
wsl --set-version Ubuntu-22.04 2
```

A conversão demora alguns minutos.

---

## Passo 4 — Limitar recursos do WSL

Por omissão o WSL pode consumir até 50% da RAM do sistema. Com 8 GB isso deixa o Windows sem folga.

Criar o ficheiro `C:\Users\<utilizador>\.wslconfig`:

```ini
[wsl2]
memory=6GB
processors=4
swap=2GB
localhostForwarding=true
```

Aplicar:

```powershell
wsl --shutdown
```

E voltar a abrir o Ubuntu.

| RAM da máquina | memory sugerido |
|---|---|
| 8 GB | 5–6 GB |
| 16 GB | 10–12 GB |
| 32 GB | 16–24 GB |

---

## Passo 5 — Atualizar o Ubuntu

Dentro do Ubuntu:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git make jq unzip ca-certificates
```

---

## Passo 6 — Docker Desktop com integração WSL

1. Descarregar de `docker.com/products/docker-desktop` e instalar.
2. **Settings → General** → confirmar **Use the WSL 2 based engine** ✔
3. **Settings → Resources → WSL Integration** → ativar `Ubuntu-22.04` ✔
4. **Apply & Restart**

> Sem o passo 3, o comando `docker` não existe dentro do Ubuntu.

Verificar dentro do Ubuntu:

```bash
docker version
docker run --rm hello-world
```

---

## Passo 7 — Onde ficam os ficheiros

| Caminho | O que é |
|---|---|
| `\\wsl$\Ubuntu-22.04\home\<user>` | home do Linux, acessível no Explorador do Windows |
| `/mnt/c/Users/<user>` | disco C: do Windows, visto de dentro do Linux |

**Regra importante para performance:** guardar os projetos **dentro** do sistema de ficheiros do Linux (`~/projects`), nunca em `/mnt/c/`. O acesso cruzado é muito mais lento e prejudica builds Docker.

```bash
mkdir -p ~/projects
cd ~/projects
```

---

## Passo 8 — Verificação final

```bash
# no Ubuntu
uname -a                 # deve mostrar kernel Linux ... WSL2
free -h                  # memória atribuída, deve refletir o .wslconfig
nproc                    # número de processadores
docker version           # cliente e servidor a responder
docker run --rm hello-world
```

Checklist:

- [ ] `wsl -l -v` mostra `Ubuntu-22.04  Running  2`
- [ ] `.wslconfig` criado e aplicado
- [ ] `docker run hello-world` funciona dentro do Ubuntu
- [ ] pasta `~/projects` criada no sistema de ficheiros Linux

---

## Problemas conhecidos

### `WslRegisterDistribution failed with error: 0x80370102`

Virtualização desativada na BIOS. Ver passo 0.2.

### `Erro 0x800701bc — WSL 2 requires an update to its kernel component`

Instalar o pacote de `https://aka.ms/wsl2kernel` e reiniciar.

### `The remote procedure call failed (0x800706be)`

```powershell
wsl --shutdown
net stop LxssManager
net start LxssManager
```

### Docker não aparece dentro do Ubuntu

Integração WSL desativada no Docker Desktop. Ver passo 6.3.

### WSL a consumir toda a RAM (processo `Vmmem`)

Falta o `.wslconfig`. Ver passo 4.

### Sem acesso à internet dentro do WSL

```bash
sudo rm /etc/resolv.conf
sudo bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
sudo bash -c 'echo "[network]" > /etc/wsl.conf'
sudo bash -c 'echo "generateResolvConf = false" >> /etc/wsl.conf'
```

Depois `wsl --shutdown` no PowerShell.

### Relógio dessincronizado após suspender o portátil

```bash
sudo hwclock -s
```

Provoca erros de TLS em `apt` e `docker pull`.

---

## Comandos de gestão do WSL

```powershell
wsl -l -v                          # listar distribuições e versões
wsl --shutdown                     # desligar tudo (aplica .wslconfig)
wsl --terminate Ubuntu-22.04       # desligar apenas uma
wsl --export Ubuntu-22.04 D:\backup-ubuntu.tar     # backup completo
wsl --import Ubuntu-22.04 D:\wsl D:\backup-ubuntu.tar   # restaurar
wsl --unregister Ubuntu-22.04      # apagar a distribuição (destrutivo)
```

> O `--export` é a forma mais simples de fazer backup de todo o ambiente antes de experiências arriscadas.

---

## Registo

**Máquina:** ALIEN — AMD Ryzen 9 7900X (12C/24T), 32 GB RAM, Windows 11 Pro 25H2 (build 26200.8875)
**Utilizador Linux:** `renat`
**Distribuição:** Ubuntu 22.04 LTS

| Data | Passo | Resultado | Notas |
|---|---|---|---|
| 10/08/2026 | Verificação do sistema | ok | Windows 11 Pro 25H2, WSL não instalado |
| 10/08/2026 | `wsl --install -d Ubuntu-22.04` | ok | WSL 2.7.11 instalado; **não foi preciso reiniciar** |
| 10/08/2026 | Criação do utilizador | ok | password falhou à primeira por não coincidir; repetida com sucesso |
| 10/08/2026 | `wsl -l -v` | **Ubuntu-22.04 · Running · 2** | confirmado em WSL2 |
| 10/08/2026 | `.wslconfig` aplicado | **ok** | `free -h` mostra 15 GiB e 4 GiB de swap — confirmado |
| 10/08/2026 | Docker Desktop instalado | ok | v4.86.0, per-user installation, backend WSL2 |
| 10/08/2026 | Integração WSL ativada | ok após 3 tentativas | ver notas abaixo |
| 10/08/2026 | `docker run hello-world` como `renat` | **ok** | Docker 29.7.2 |

### Notas desta instalação

- Em Windows 11 25H2 o `wsl --install` já não exige reinício — as funcionalidades do Windows necessárias já vêm ativas.
- A password é pedida duas vezes e não aparece no ecrã. Se não coincidirem, o sistema pergunta `Try again? [y/N]` — responder `y`.
- A shell abre em `/mnt/c/Windows/system32` quando lançada a partir do PowerShell. Passar sempre para `~` antes de trabalhar (ver passo 7 sobre performance).

### Problemas encontrados nesta instalação

**1. `permission denied` no socket do Docker**

Ao correr `docker run hello-world` pela primeira vez:

```
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

Causa: o utilizador não pertencia ao grupo `docker`.

Solução correta:
```bash
sudo usermod -aG docker $USER
```
seguido de `wsl --shutdown` no PowerShell, porque a mudança de grupo só se aplica numa sessão nova.

> Contornar com `sudo su` funciona, mas cria problemas depois — o kubeconfig vai parar a `/root/.kube/config` e os ficheiros ficam com dono errado. Não fazer.

**2. `WSL integration with distro 'Ubuntu-22.04' unexpectedly stopped`**

```
DockerDesktop/Wsl/ExecError: install: cannot stat
'/mnt/wsl/docker-desktop/docker-desktop-user-distro': No such file or directory
```

Causa: foi corrido `wsl --shutdown` com o Docker Desktop aberto. O ponto de montagem `/mnt/wsl/docker-desktop` desapareceu e o Docker Desktop deixou de conseguir copiar o binário do proxy para dentro da distribuição.

**A ordem de arranque importa:**

1. Fechar todas as janelas do Ubuntu
2. Sair do Docker Desktop pelo tray (*Quit Docker Desktop*)
3. `wsl --shutdown` no PowerShell
4. Confirmar com `wsl -l -v` que tudo está `Stopped`
5. Abrir o **Docker Desktop primeiro** e esperar por *Engine running*
6. Só então abrir o Ubuntu

Seguida esta ordem, a integração ficou estável.
