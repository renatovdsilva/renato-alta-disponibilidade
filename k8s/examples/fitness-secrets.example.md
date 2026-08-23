# FitnessPHIVE — Secrets, como recriar

Nenhum destes ficheiros existe no repositório, e não deve passar a existir.
Aqui ficam só os comandos para os recriar num cluster novo.

Deliberadamente em Markdown e não em YAML: não há forma de escrever um exemplo
de Secret TLS que não pareça um sítio conveniente para colar a chave privada.

---

## 1. `fitness-basic-auth`

Autenticação básica no Ingress. O NGINX espera um Secret com a chave `auth`,
no formato do `htpasswd`.

```bash
sudo apt install -y apache2-utils      # se o htpasswd não existir

htpasswd -c /tmp/auth <utilizador>     # pede a password
kubectl create secret generic fitness-basic-auth -n fitness --from-file=/tmp/auth
shred -u /tmp/auth                     # apagar o ficheiro em claro
```

Anotações correspondentes no Ingress:

```yaml
nginx.ingress.kubernetes.io/auth-type: basic
nginx.ingress.kubernetes.io/auth-secret: fitness-basic-auth
nginx.ingress.kubernetes.io/auth-realm: "Area restrita"   # sem acentos
```

> O `auth-realm` **sem acentos** não é preciosismo: o valor vai para um
> cabeçalho HTTP, que é ASCII. Com um caráter acentuado, o webhook de
> validação do NGINX rejeita o Ingress inteiro.

## 2. `fitness-tls` e `fitness-tls-public`

Certificados. O `fitness-tls` cobre `fitness.localhost` (autoassinado chega);
o `fitness-tls-public` cobre `renatovdsilva.ddns.net` e deve ser emitido por
uma autoridade reconhecida, senão o browser avisa.

```bash
# autoassinado, para o domínio local
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=fitness.localhost"

kubectl create secret tls fitness-tls -n fitness \
  --cert=/tmp/tls.crt --key=/tmp/tls.key

shred -u /tmp/tls.key /tmp/tls.crt
```

Para o público, a partir dos ficheiros emitidos:

```bash
kubectl create secret tls fitness-tls-public -n fitness \
  --cert=fullchain.pem --key=privkey.pem
```

**A fazer:** `cert-manager` com Let's Encrypt, que emite e renova sozinho e
acaba com o passo manual. Já está nas melhorias futuras do doc 10.

---

## Verificar que existem antes do primeiro sync

```bash
kubectl -n fitness get secret fitness-basic-auth fitness-tls fitness-tls-public
```

Se algum faltar, o Ingress é criado mas devolve erro — e o diagnóstico não é
óbvio, porque o Ingress em si aparece como válido.
