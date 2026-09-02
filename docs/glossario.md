# Glossário — dizer as coisas pelo nome

Cada termo tem a definição curta e, quando existe, **o exemplo concreto deste
projeto**. É a terceira coluna que faz a diferença numa entrevista: qualquer um
decora a definição, poucos conseguem apontar ao que fizeram.

---

## Entrega de software

**CI — Integração Contínua**
A cada commit, um sistema automático constrói e testa o código.
*Aqui:* GitHub Actions corre `mkdocs build --strict` e publica a documentação.

**CD — Entrega Contínua**
O artefacto fica sempre pronto para produção, mas alguém decide quando vai.

**CD — Implantação Contínua**
Vai para produção sozinho, sem intervenção humana.
*Aqui:* ArgoCD com sync automático.

**Pipeline**
A sequência de passos automáticos entre o commit e a produção.

**Artefacto**
O resultado da build. Uma imagem de contentor, um binário, um pacote.

**GitOps**
O estado desejado da infraestrutura vive em Git e um agente no cluster
reconcilia continuamente o real com o desejado. Modelo *pull*, não *push*.
*Aqui:* ArgoCD com `selfHeal` e `prune`.

**Reconciliação**
O processo de comparar o estado real com o desejado e corrigir a diferença.
*Aqui:* apaguei um Ingress com kubectl e o ArgoCD repô-lo em segundos.

**Drift**
Divergência entre o que está declarado e o que está a correr. Normalmente
resulta de alterações manuais.

**Rollback**
Voltar à versão anterior. Em GitOps é um `git revert`.

---

## Infraestrutura

**IaC — Infraestrutura como Código**
Descrever a infraestrutura em ficheiros versionados em vez de a configurar à mão.

**Declarativo vs Imperativo**
Declarativo descreve o *estado final*; imperativo descreve os *passos*.
Kubernetes, Terraform e Ansible são declarativos; um script bash é imperativo.

**Idempotência**
Aplicar a mesma operação várias vezes dá sempre o mesmo resultado.
*Aqui:* o playbook de Ansible correu duas vezes — `changed=1` e depois
`changed=0`.

**Provisionar vs Configurar**
Terraform **cria** a infraestrutura (VMs, redes, load balancers).
Ansible **configura** o que já existe (pacotes, ficheiros, serviços).

**Dry-run**
Simular a execução sem alterar nada.
*Aqui:* `ansible-playbook --check` e `kubectl --dry-run=client`.

---

## Kubernetes

**Pod** — a unidade mínima. Um ou mais contentores que partilham rede e volumes.
**Deployment** — gere réplicas de pods sem estado, com atualizações graduais.
**StatefulSet** — para aplicações com estado. Identidade estável e volume próprio.
*Aqui:* o PostgreSQL.
**DaemonSet** — um pod por nó.
**Service** — nome estável e balanceamento para um conjunto de pods.
**Ingress** — encaminhamento HTTP por domínio, terminação TLS.
**Namespace** — separação lógica de recursos dentro do cluster.
**ConfigMap e Secret** — configuração e dados sensíveis, fora da imagem.
**PV e PVC** — o volume e o pedido de volume.
**Control plane** — apiserver, etcd, scheduler, controller-manager.
**kubelet** — o agente em cada nó que garante que os pods declarados estão a correr.
**Reconciliation loop** — o padrão base do Kubernetes: observar, comparar, corrigir.

---

## Fiabilidade

**Alta disponibilidade** — o sistema continua a servir mesmo com falha de um
componente. *Aqui:* três nós e réplicas.
**Tolerância a falhas** — capacidade de aguentar falhas sem perder serviço.
**Ponto único de falha** — o componente que, ao falhar, derruba tudo.
*Aqui:* eliminei-o na LCR com redundância de fibra e ligação sem fios ponto a ponto.
**RTO** — quanto tempo se demora a repor o serviço.
**RPO** — quantos dados se pode perder, medido em tempo.
**SLI, SLO, SLA** — o que se mede, o alvo interno, e o compromisso contratual.
**Observabilidade** — conseguir perceber o que se passa lá dentro a partir do que
sai. Métricas, logs e traces.
*Aqui:* Prometheus e Grafana com regras de alerta próprias.
**Blast radius** — o alcance do estrago quando algo corre mal.

---

## Contentores

**Imagem** — o pacote imutável. **Contentor** — a instância a correr.
**Registry** — onde as imagens ficam guardadas.
**Multi-stage build** — uma fase compila, outra só leva o resultado. Imagem final
mais pequena e sem ferramentas de compilação.
**Camadas** — cada instrução do Dockerfile cria uma camada, reaproveitada em cache.

---

## Redes e segurança

**NAT, DMZ, port forwarding** — tradução de endereços, exposição total de um host,
e abertura de uma porta específica.
*Aqui:* removi a DMZ e o encaminhamento de 3389 depois de encontrar tentativas de
login vindas da internet.
**VPN em malha** — cada dispositivo liga diretamente aos outros, em vez de tudo
passar por um servidor central. *Aqui:* Tailscale, sobre WireGuard.
**NLA** — autenticação antes de estabelecer a sessão RDP.
**Least privilege** — dar só as permissões necessárias.
**Defesa em profundidade** — várias camadas, de modo a que falhar uma não chegue.

---

## Como usar isto numa entrevista

Não recites definições. O padrão que funciona é:

> **termo → o que significa em uma frase → o que fizeste com isso**

Exemplo:

> "Idempotência é uma operação dar sempre o mesmo resultado, corra uma ou dez
> vezes. Foi o que verifiquei no meu playbook de Ansible: à primeira mudou uma
> coisa, à segunda ficou tudo a zero."

Vale mais do que qualquer definição de manual.
