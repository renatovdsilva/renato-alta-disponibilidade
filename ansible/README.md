# Ansible — automação da preparação do ambiente

Esta pasta automatiza os passos que antes eram feitos à mão antes de o
`scripts/bootstrap.sh` poder correr.

## Porquê Ansible e não um script

O `bootstrap.sh` já faz o trabalho, mas é imperativo: descreve **os passos**.
O Ansible é declarativo — descreve **o estado final desejado** e só age quando
a máquina não está nesse estado.

Na prática isso significa três coisas:

- **Idempotência.** Correr o playbook dez vezes seguidas dá o mesmo resultado
  que correr uma. O script tinha de verificar cada caso à mão.
- **`--check`.** Dá para ver o que mudaria sem mudar nada. Um script não.
- **Escala.** O mesmo playbook aplica-se a um portátil ou a vinte servidores,
  mudando apenas o inventário.

## Ficheiros

| Ficheiro | O que faz |
|---|---|
| `inventory.ini` | Define onde o Ansible atua. Hoje é a máquina local; o grupo `k8s_nodes` fica preparado para quando houver nós reais. |
| `ferramentas.yml` | Instala e fixa as versões de `kubectl`, `helm` e `k3d`, mais os pacotes de sistema. |

## Como correr

```bash
# instalar o Ansible, uma vez só
sudo apt update && sudo apt install -y ansible

cd ansible

# ver o que mudaria, sem alterar nada
ansible-playbook -i inventory.ini ferramentas.yml --check --diff

# aplicar
ansible-playbook -i inventory.ini ferramentas.yml --ask-become-pass
```

## Notas

O `kubectl` é instalado a partir do binário oficial e não do apt, porque a
versão tem de acompanhar a do k3s do cluster (v1.35.5) e os repositórios da
distribuição andam quase sempre atrasados. A versão está fixada em `vars`, no
topo do playbook — é lá que se muda.

## Por fazer

- [ ] Playbook para instalar o Docker Engine, para o caso de a máquina não ter
      Docker Desktop.
- [ ] Playbook que substitua o `bootstrap.sh` por completo, criando o cluster e
      instalando o Ingress NGINX e o ArgoCD.
- [ ] Módulos `kubernetes.core` em vez de chamadas a `kubectl`.
