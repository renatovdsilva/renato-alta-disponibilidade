# Plano de estudo — CKA

Certified Kubernetes Administrator, The Linux Foundation.
Plano de 12 semanas, cerca de 2h por dia útil. Começo: 1 de setembro de 2026.
Data alvo do exame: **final de novembro de 2026**.

---

## O exame

- **Formato:** prático, num cluster real. Sem escolha múltipla.
- **Duração:** 2 horas, 17 tarefas.
- **Nota mínima:** 66%.
- **Documentação permitida:** kubernetes.io durante o exame. Saber navegá-la
  depressa vale tanto como saber a matéria.
- **Repetição:** o voucher inclui uma segunda tentativa.

### Domínios e pesos

| Domínio | Peso |
|---|---|
| Troubleshooting | 30% |
| Cluster Architecture, Installation & Configuration | 25% |
| Services & Networking | 20% |
| Workloads & Scheduling | 15% |
| Storage | 10% |

**Leitura estratégica:** troubleshooting é quase um terço do exame. É também
onde tens mais vantagem — dezoito anos a resolver incidentes. Não é matéria
nova, é a tua matéria noutra sintaxe.

---

## A tua vantagem

Já tens cluster de três nós a correr, com aplicações reais, GitOps, ingress,
TLS, PostgreSQL em StatefulSet e monitorização. A maioria dos candidatos estuda
em ambientes descartáveis; tu tens um que já partiu e que já reparaste.

Aproveita isso: **todos os exercícios deste plano fazem-se no teu cluster.**

---

## Semanas 1 e 2 — Fundamentos e velocidade

O exame é contra o relógio. Nesta fase treina-se a mecânica, não a teoria.

- [ ] Configurar `alias k=kubectl` e autocompletion
- [ ] Dominar `kubectl explain`, `-o yaml`, `--dry-run=client`
- [ ] Gerar manifests por linha de comando em vez de escrever à mão
- [ ] `kubectl run`, `create deployment`, `expose`, `scale`, `edit`, `patch`
- [ ] Trabalhar com contextos e namespaces (`kubectl config use-context`)
- [ ] Ler e navegar a documentação em kubernetes.io **cronometrado**

**Meta:** criar um Deployment exposto por Service em menos de 60 segundos, sem
copiar de lado nenhum.

---

## Semanas 3 e 4 — Workloads & Scheduling (15%)

- [ ] Deployments, ReplicaSets, rolling updates, rollback (`rollout undo`)
- [ ] DaemonSets, Jobs, CronJobs
- [ ] ConfigMaps e Secrets, como variáveis e como volumes
- [ ] Resource requests e limits; classes de QoS
- [ ] `nodeSelector`, affinity e anti-affinity
- [ ] Taints e tolerations
- [ ] Probes: liveness, readiness, startup
- [ ] Helm e Kustomize (entraram no currículo)

**Prática no teu cluster:** já usas Helm no chart da Quinta e Kustomize no
fitness. Refaz esses casos à mão, sem ArgoCD, para perceber o que ele faz por ti.

---

## Semanas 5 e 6 — Services & Networking (20%)

- [ ] ClusterIP, NodePort, LoadBalancer, ExternalName
- [ ] Endpoints e como o Service encontra os pods
- [ ] Ingress e IngressClass
- [ ] **Gateway API** — novidade no currículo: Gateway, GatewayClass, rotas
- [ ] CoreDNS e resolução dentro do cluster
- [ ] NetworkPolicies (ingress e egress)
- [ ] Plugins CNI, o essencial

**Prática:** tens Ingress NGINX com TLS e basic auth a correr. Acrescenta
NetworkPolicies aos teus namespaces e experimenta a Gateway API a par do Ingress.

**Nota:** o erro do 503 com upstream vazio, por teres referido a porta por nome,
é exatamente o tipo de coisa que o exame testa em troubleshooting.

---

## Semanas 7 e 8 — Storage (10%) e Cluster Architecture (25%)

**Storage**

- [ ] Volumes, PersistentVolume, PersistentVolumeClaim
- [ ] StorageClasses e provisionamento dinâmico
- [ ] Access modes e reclaim policies
- [ ] StatefulSets e volumeClaimTemplates

Já fizeste isto para o PostgreSQL. Revê porque escolheste ReadWriteOnce e o que
isso te obrigou a fazer no Deployment (`strategy: Recreate`).

**Cluster Architecture**

- [ ] Componentes: kube-apiserver, etcd, scheduler, controller-manager, kubelet, kube-proxy
- [ ] RBAC: Roles, ClusterRoles, bindings, ServiceAccounts
- [ ] `kubeadm`: criar cluster, juntar nós, **fazer upgrade de versão**
- [ ] **Backup e restauro do etcd** — cai quase sempre
- [ ] Certificados e CSRs
- [ ] CRDs e operadores

**Atenção:** o teu cluster é k3d, que abstrai o kubeadm. Para esta parte precisas
de um ambiente separado — duas VMs no VirtualBox ou o killercoda.com, que é
gratuito e simula o exame.

---

## Semanas 9 e 10 — Troubleshooting (30%)

O domínio mais pesado. Método antes de comandos.

- [ ] Pods: `describe`, `logs`, `logs --previous`, `events`
- [ ] Estados: Pending, ImagePullBackOff, CrashLoopBackOff, OOMKilled, Evicted
- [ ] Nós: `kubectl get nodes`, `journalctl -u kubelet`, pressão de recursos
- [ ] Componentes do control plane em falha
- [ ] Problemas de rede: DNS, Service sem endpoints, NetworkPolicy a bloquear
- [ ] `kubectl debug` e contentores efémeros

**Rotina:** parte o teu próprio cluster de propósito e repara. Apaga um Secret,
troca a porta de um Service, mete um limite de memória absurdamente baixo,
suspende um nó. Documenta cada caso — diagnóstico e correção.

Isto também te dá material real para entrevistas.

---

## Semanas 11 e 12 — Simulados

- [ ] killer.sh — dois simulados incluídos no voucher. São mais difíceis do que
      o exame real, de propósito. Usa o primeiro na semana 11.
- [ ] Refazer, cronometrado, todos os exercícios em que falhaste
- [ ] Treinar gestão de tempo: saltar o que trava, voltar no fim
- [ ] Segundo simulado do killer.sh na semana 12
- [ ] Marcar o exame

---

## Recursos

- Documentação oficial: kubernetes.io — a única permitida no exame
- killercoda.com — cenários gratuitos no browser
- killer.sh — simulados, incluídos no voucher
- Curso de Mumshad Mannambeth (KodeKloud) na Udemy — o mais usado
- Repositório do exame: github.com/kodekloudhub/certified-kubernetes-administrator-course

---

## Regras de execução

- **Duas horas por dia útil**, as que ias gastar no Dota durante a semana.
  Fim de semana, jogas à vontade.
- **Estudo antes do Discord.** Regra fixa, não força de vontade.
- **Tudo prático.** Ver vídeos não conta como estudo; conta escrever YAML e
  partir coisas.
- **Registar no repositório.** Cria `docs/cka/` e vai documentando o que
  aprendes. Serve para fixar e serve de portfólio.

---

## Custo

O exame ronda os 445 dólares, com descontos frequentes. Não é para agora — é
para quando o dinheiro estabilizar. Estudar não custa nada e o valor entra no
currículo antes do certificado: "em preparação para o CKA" já conta.

---

## Revisão

No fim de cada bloco de duas semanas, uma pergunta só: **consigo fazer isto sem
consultar nada?** Se não, repete-se o bloco. O calendário é indicativo; a
competência é que manda.
