# FitnessPHIVE — manifests para GitOps

Origem: `C:\Users\renat\Documents\FitnessPHIVE\deploy\k8s\`
Destino: esta pasta.

Esta é a aplicação com mais arestas das três: exposição pública, autenticação
básica, TLS, e um Ingress que foi corrigido à mão no cluster. **Ler a secção
"Correções feitas à mão" antes de copiar seja o que for.**

---

## O que copiar

| Ficheiro | Nota |
|---|---|
| Namespace `fitness` | |
| Deployment (1 réplica, `strategy: Recreate`) | ver nota sobre a estratégia |
| PersistentVolumeClaim (SQLite) | só se for um PVC autónomo, não um `volumeClaimTemplates` |
| Service | |
| Ingress `fitness.localhost` | |
| Ingress `fitnessphive-public` (`renatovdsilva.ddns.net`) | **com as correções aplicadas** — ver abaixo |

Sugestão de numeração:

```
00-namespace.yaml
10-pvc.yaml
20-deployment.yaml
21-service.yaml
22-ingress-local.yaml
23-ingress-public.yaml
```

## O que NÃO copiar

- **`Secret` `fitness-basic-auth`** — contém o ficheiro `auth` com o hash da
  password.
- **`Secret` `fitness-tls`** e **`fitness-tls-public`** — chaves privadas de
  certificados. Nunca, em nenhuma circunstância, num repositório público.
- Ficheiros `.htpasswd`, certificados `.key`, `.pem` ou `.crt`.
- A base de dados SQLite, se estiver algures na pasta.

## Correções feitas à mão que TÊM de ir para o ficheiro

O Ingress `fitnessphive-public` foi corrigido com `kubectl` depois de criado.
**Essas duas correções têm de estar nos manifests antes do primeiro sync**,
senão o ArgoCD repõe a versão partida — é literalmente a função dele.

| Correção | De | Para | Porquê |
|---|---|---|---|
| Porta do backend | `port: { name: http }` | `port: { number: 80 }` | o nome tem de coincidir com uma porta **nomeada no Service**; se o Service expõe a porta sem nome, a referência por nome não resolve |
| `nginx.ingress.kubernetes.io/auth-realm` | texto com acentos | texto sem acentos | o webhook de validação do NGINX rejeita o Ingress — os cabeçalhos HTTP são ASCII, e um valor não-ASCII na anotação torna a configuração inválida |

Confirmar como está no cluster **agora** e transcrever para o ficheiro:

```bash
kubectl -n fitness get ingress fitnessphive-public -o yaml \
  | grep -A6 "auth-realm\|backend\|port"
```

Se o ficheiro de origem tiver a versão antiga, corrigir o ficheiro. Não vale a
pena voltar a aplicar o patch no cluster: assim que o ArgoCD assumir, é o Git
que manda.

## Notas de operação

**`strategy: Recreate` e PVC `ReadWriteOnce`.** É a combinação correta para
SQLite num volume que só pode ser montado por um nó: com `RollingUpdate`, o pod
novo tentaria montar o volume antes de o antigo o largar, e ficaria em
`Pending`. A consequência assumida é que **cada sync com alteração ao
Deployment implica downtime** — o pod antigo morre antes de o novo arrancar.

Não é defeito. É a troca que se faz quando o estado está num ficheiro e não num
servidor de base de dados — o mesmo raciocínio da decisão D9, resolvido em
sentido contrário porque aqui não há requisito de alta disponibilidade.

## Antes de commitar

```bash
grep -ril "kind: Secret" k8s/apps/fitness/
grep -rl "BEGIN.*PRIVATE KEY\|htpasswd" k8s/apps/fitness/
```

Ambos devem devolver vazio.
