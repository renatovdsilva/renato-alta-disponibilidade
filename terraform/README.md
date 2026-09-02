# Terraform — a plataforma

Cria o cluster e a camada de plataforma de forma declarativa. A partir daí, quem
gere as aplicações é o ArgoCD, a partir do Git.

## A divisão de responsabilidades

| Camada | Ferramenta | O que faz |
|---|---|---|
| Estação de trabalho | **Ansible** | Instala kubectl, helm, k3d |
| Plataforma | **Terraform** | Cria o cluster, Ingress NGINX, namespaces, ArgoCD |
| Aplicações | **ArgoCD** | Faz o deploy do que está em `k8s/apps/`, a partir do Git |

Cada uma tem o seu domínio e nenhuma pisa a outra. É esta separação que se
pergunta em entrevistas quando falam de Terraform *versus* Ansible: **o Terraform
provisiona, o Ansible configura, o ArgoCD entrega.**

## Porquê Terraform e não o `bootstrap.sh`

O script funciona. A diferença está em três coisas:

**Estado.** O Terraform guarda um registo do que criou. Sabe o que existe e o que
não existe, sem ter de ir verificar caso a caso.

**Plano antes de agir.** `terraform plan` mostra exatamente o que vai criar,
alterar ou destruir, antes de mexer em nada. Um script não tem equivalente.

**Destruição limpa.** `terraform destroy` remove tudo o que criou, na ordem certa.
É o que torna o teste de reconstrução de raiz trivial em vez de arriscado.

## Como usar

```bash
cd terraform

terraform init      # descarrega os providers
terraform plan      # mostra o que vai acontecer, sem alterar nada
```

### O apply é em duas fases, e há uma razão

```bash
# 1) primeiro só o cluster
terraform apply -target=k3d_cluster.alta_disponibilidade

# 2) depois o resto
terraform apply
```

**Porquê.** Os providers do Kubernetes e do Helm são configurados na fase de
plano, antes de qualquer recurso existir. Precisam do contexto
`k3d-<cluster>` no kubeconfig — que só passa a existir depois de o cluster ser
criado. Se se correr tudo de uma vez, o Terraform falha com
`context "k3d-..." does not exist`.

Não é um defeito desta configuração: é uma limitação conhecida do Terraform.
A configuração de um provider não pode depender de um recurso criado no mesmo
apply. Por isso é que, em ambientes a sério, o provisionamento do cluster e o
que se instala em cima dele vivem em estados separados — normalmente duas pastas
ou dois workspaces, aplicados por ordem.

Aqui resolve-se com `-target`, que é suficiente para um projeto desta dimensão.

Para destruir e recriar do zero — que é o teste que falta fazer ao projeto:

```bash
terraform destroy
terraform apply
```

Para um cluster de teste em paralelo, sem tocar no principal:

```bash
terraform apply -var="cluster_name=teste" -var="agents=1"
```

## Estado

O ficheiro `terraform.tfstate` fica local e **está no .gitignore**, porque pode
conter valores sensíveis. Num contexto de equipa, o estado vive num backend
remoto — S3 com bloqueio em DynamoDB, Azure Storage, ou Terraform Cloud — para
que duas pessoas não apliquem ao mesmo tempo.

Aqui, com uma máquina só, o estado local chega.

## O que NÃO está aqui, de propósito

**Secrets.** Continuam a ser criados à mão e fora do Git. O Terraform guardaria
os valores em claro no ficheiro de estado, o que é pior do que o problema que
resolveria.

**As aplicações.** São do ArgoCD. Se o Terraform também as gerisse, passava a
haver duas fontes da verdade a disputar o mesmo recurso.

## Por fazer

- [ ] Backend remoto para o estado
- [ ] cert-manager e ClusterIssuer do Let's Encrypt
- [ ] Módulo separado para a camada de monitorização
