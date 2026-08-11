# 10 — Decisões de arquitetura

Registo das escolhas e das razões. Serve para responder a "porque é que fizeste assim?".

---

## D1 — k3d em vez de máquina virtual

**Contexto:** era preciso um Kubernetes multi-nó num portátil Windows.

**Alternativas:** VirtualBox com VMs Ubuntu; minikube; kind; Docker Desktop Kubernetes.

**Decisão:** k3d (k3s dentro de contentores Docker) sobre WSL2.

**Razões:** o WSL2 já é uma máquina virtual com kernel Linux real, portanto uma VM tradicional acrescentaria uma camada de virtualização em cima de outra. O k3d cria três nós em segundos com uma fração da RAM, e o k3s é certificado pela CNCF — a API é idêntica à de qualquer cluster.

**Custo:** os "nós" partilham o kernel do host, portanto não se pode testar falha real de hardware nem redes fisicamente separadas.

---

## D2 — Ingress NGINX em vez de Traefik

**Contexto:** o k3s traz Traefik por omissão.

**Decisão:** desativar o Traefik e instalar Ingress NGINX.

**Razão:** as ofertas de emprego pedem NGINX com muito mais frequência. O objetivo do laboratório é também alinhar com o mercado.

---

## D3 — Duas réplicas por aplicação

**Razão:** com uma réplica não há alta disponibilidade nenhuma — matar o pod derruba o serviço. Com duas, é possível demonstrar rolling update sem downtime e recuperação automática.

**Custo:** o dobro da memória. Aceitável nesta escala.

---

## D4 — Requests e limits em todos os containers

**Razão:** sem `requests`, o scheduler decide às cegas. Sem `limits`, uma fuga de memória numa aplicação afeta todo o nó. É a diferença entre um cluster de brincadeira e um cluster operado.

---

## D5 — Helm em vez de kubectl apply

**Razão:** permite valores diferentes por ambiente sem duplicar ficheiros, e dá histórico com rollback. É também o formato que o ArgoCD consome naturalmente.

---

## D6 — GitOps com ArgoCD

**Razão:** torna cada alteração um commit auditável e elimina o drift entre o que está no Git e o que está no cluster. É a prática atual do mercado e diferencia o projeto.

---

## D7 — Nenhum segredo no repositório

**Razão:** o repositório é público. Passwords do Grafana e do ArgoCD passam por `--set` ou por Secrets criados fora do Git.

**A melhorar:** integrar Sealed Secrets ou External Secrets para poder versionar segredos cifrados.

---

## D8 — MySQL dentro do cluster, como StatefulSet

**Contexto:** a Briosa Agenda precisa de MySQL. O config da aplicação apontava para `127.0.0.1:3306`, ou seja, uma base de dados instalada ao lado da aplicação.

**Alternativas:**

| Opção | Prós | Contras |
|---|---|---|
| Serviço gerido (Cloud SQL, RDS, PlanetScale) | backups, HA e patches tratados | custo mensal; nada para demonstrar aqui |
| MySQL no WSL, fora do cluster | simples de arrancar | fica fora do domínio do Kubernetes; o cluster deixa de ser reprodutível por um comando |
| **StatefulSet no cluster com PVC** | exercita gestão de estado | é preciso tratar backups e ciclo de vida à mão |

**Decisão:** MySQL no cluster, como StatefulSet com `volumeClaimTemplates`, Service headless e credenciais em Secret. Dados de teste, nunca dados reais.

**Razões:** em produção a escolha seria um serviço gerido — não há vantagem em operar uma base de dados à mão quando alguém o faz melhor e com SLA. Aqui a escolha é deliberadamente a oposta, porque o objetivo do laboratório é precisamente exercitar aquilo que um serviço gerido esconde: `StatefulSet`, `PersistentVolumeClaim`, Service headless com DNS estável por pod, `Secret` e ordem de arranque com probes. É também matéria de exame do CKA, ao contrário de configurar um endpoint externo.

**Porquê StatefulSet e não Deployment:** um Deployment com um PVC funciona com uma réplica, mas todas as réplicas partilhariam o mesmo volume se alguém escalasse — e duas instâncias de MySQL sobre o mesmo datadir corrompem a base. O `volumeClaimTemplates` dá a cada réplica o seu volume, e a identidade estável (`mysql-0`) permite endereçar um pod concreto pelo DNS.

**Custo assumido:**

- Sem réplicas nem failover: o StatefulSet tem uma réplica. Se o nó cair, a base fica indisponível até o pod voltar. HA de MySQL exige replicação e um operador — fora do âmbito.
- O `storageClass` `local-path` do k3s prende o volume ao nó onde o pod foi agendado.
- Backups por fazer. Fica em melhorias futuras.
- O schema é aplicado por `/docker-entrypoint-initdb.d` e só corre na primeira inicialização; alterações posteriores obrigam a recriar o PVC.

---

## D9 — Migrar a Quinta do Calvário de SQLite para PostgreSQL

**Contexto:** o `schema.prisma` da Quinta usava `provider = "sqlite"` com `url = "file:./dev.db"`. O SQLite é uma biblioteca que escreve num ficheiro local — não há servidor, não há ligação por rede.

**O problema:** num Deployment com duas réplicas, só há dois desfechos possíveis, e ambos são maus.

| Montagem | O que acontece |
|---|---|
| Cada pod com o seu ficheiro | Cada réplica tem uma base diferente. Uma reserva criada num pod não existe no outro, e o balanceamento do Service decide qual dos dois responde. Os dados divergem em silêncio. |
| PVC `ReadWriteMany` partilhado | Dois processos a escrever no mesmo ficheiro SQLite sobre rede. O locking do SQLite não foi feito para isto: corrupção da base é o resultado esperado, não o improvável. |

A única forma de manter SQLite com segurança seria fixar a Quinta em **uma réplica**.

**Alternativa rejeitada:** manter SQLite e reduzir a Quinta a uma réplica. Rejeitada porque contradiz o objetivo declarado do projeto. O `00-ponto-de-partida.md` diz "alta disponibilidade demonstrável" e a decisão D3 diz que uma réplica não é alta disponibilidade nenhuma. Ficaria a aplicação principal do laboratório de HA a ser a única incapaz de o demonstrar — e o teste de resiliência do doc 04, que é o que se conta em entrevista, deixaria de fazer sentido.

**Decisão:** migrar para PostgreSQL, a correr no cluster como StatefulSet com PVC, Service headless e credenciais em Secret. A `url` do datasource passa a `env("DATABASE_URL")`, alimentada pelo Secret. Nunca hardcoded.

**Razões:** o Postgres é um servidor a que várias réplicas se ligam por rede, o que devolve à Quinta as duas réplicas e o rolling update sem downtime. É também o provider que o Prisma melhor suporta e o que aparece na maioria das ofertas.

**Custo assumido:**

- Deixa de haver "clonar e correr": passa a ser preciso uma base de dados a correr. Compensado pelo `bootstrap.sh`.
- Mais um componente com estado a operar — mesmos custos do D8 (uma réplica, sem failover, backups por fazer, volume preso ao nó por causa do `local-path`).
- A migração exige gerar migrações do Prisma de raiz: o SQLite e o Postgres não têm os mesmos tipos, e as migrações existentes (se houvesse) não se reaproveitam.

**Consequência para o D8:** o projeto passa a ter duas bases de dados diferentes, MySQL para a Briosa e PostgreSQL para a Quinta. Não é acidente nem indecisão — cada aplicação usa aquilo com que já foi escrita. Uniformizar obrigaria a reescrever uma delas, sem ganho nenhum para o laboratório.

---

## Dívida técnica registada

Não são decisões de arquitetura, são coisas que ficam por corrigir e que convém não esquecer.

| # | Onde | O quê | Porque importa |
|---|---|---|---|
| DT1 | Quinta — `next.config.mjs` | `eslint.ignoreDuringBuilds: true` e `typescript.ignoreBuildErrors: true` | O build passa mesmo com erros de tipos e de lint. Uma imagem pode ser publicada com código que não compila em condições, e a falha só aparece em runtime. Mantido por agora para desbloquear a containerização; a corrigir antes de haver pipeline de CI, senão o CI valida um build que ignora os erros que devia apanhar. |
| DT5 | Quinta — dependências | 2 vulnerabilidades **high** reportadas pelo `npm audit` em 11/08/2026 | Por triar: ver se são exploráveis a partir do código da aplicação ou se estão em dependências de desenvolvimento, que não entram na imagem final. `npm audit fix` sem olhar pode subir versões major e partir o build. A imagem devia passar por um scan (Trivy) antes de ir para o cluster — já está nas melhorias futuras. |
| DT2 | Briosa — `app/config/database.php` | Password em texto limpo no histórico do Git público | Rodar a credencial não a remove dos commits antigos. Ver `apps/briosa-agenda/README.md`. |
| DT3 | Briosa | `app/` dentro do document root | Remediado ao nível do Apache; a correção real é reestruturar a aplicação. |
| DT4 | Ambas | Sem backups das bases de dados | Um `k3d cluster delete` leva os dados. Aceitável com dados de teste, inaceitável a partir do momento em que deixem de ser. |
| DT6 | Quinta — `.env.local` | Ficheiro com `NEXTAUTH_SECRET` criado localmente | Está no `.gitignore` e deve continuar. O secret de desenvolvimento e o do cluster são valores diferentes — não copiar um para o outro. |

---

## Melhorias futuras

- [ ] Sealed Secrets
- [ ] Backup automático do MySQL (CronJob com `mysqldump` para um PVC separado)
- [ ] Reestruturar a Briosa para tirar `app/` de dentro do document root
- [ ] cert-manager com TLS local
- [ ] Terraform para provisionar o cluster
- [ ] Pipeline de CI no GitHub Actions (build, scan com Trivy, push)
- [ ] Network policies entre namespaces
- [ ] Loki para agregação de logs
