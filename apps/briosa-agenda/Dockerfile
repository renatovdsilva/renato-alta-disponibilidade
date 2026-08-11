# syntax=docker/dockerfile:1
#
# Briosa Agenda — imagem de produção
#
# Contexto de build: a RAIZ do repositório briosatecnica-agenda.
#   cd ~/projects/briosatecnica-agenda
#   docker build -t briosa-agenda:1.0.0 .
#
# Atenção ao caminho: o código está aninhado em public_html/public_html/.
# A raiz do repositório contém apenas public_html/ e public_html.zip.

FROM php:8.2-apache

# ---------- extensões ----------
# A aplicação usa PDO com MySQL (app/config/database.php → host 127.0.0.1:3306).
# mysqli fica incluído porque código PHP antigo costuma misturar as duas APIs;
# se se confirmar que só usa PDO, remover mysqli reduz mais a imagem.
RUN set -eux; \
    a2enmod rewrite; \
    docker-php-ext-install -j"$(nproc)" pdo_mysql mysqli; \
    docker-php-source delete; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl; \
    rm -rf /var/lib/apt/lists/*

# ---------- Apache na porta 8080 ----------
# Um processo não-root não se pode ligar a portas abaixo de 1024. Para o
# container correr como www-data (princípio 3 do doc 03), o Apache passa
# a escutar na 8080. O Service do Kubernetes usa targetPort nomeado, por
# isso nada mais muda do lado do cluster além do containerPort.
RUN set -eux; \
    sed -ri 's!^Listen 80$!Listen 8080!' /etc/apache2/ports.conf; \
    sed -ri 's!<VirtualHost \*:80>!<VirtualHost *:8080>!' /etc/apache2/sites-available/000-default.conf; \
    mkdir -p /var/run/apache2 /var/lock/apache2; \
    chown -R www-data:www-data /var/run/apache2 /var/lock/apache2 /var/log/apache2

# ---------- barreira sobre a pasta app/ ----------
# A estrutura da aplicação tem app/ dentro do document root, o que expõe
# configuração e schema por HTTP. Bloqueado aqui até a aplicação ser
# reestruturada — ver "Problemas conhecidos" em apps/briosa-agenda/README.md.
# Os includes de PHP continuam a funcionar: são leituras do sistema de
# ficheiros, não pedidos HTTP.
RUN set -eux; \
    printf '%s\n' \
      '<DirectoryMatch "^/var/www/html/app/(config|database)">' \
      '    Require all denied' \
      '</DirectoryMatch>' \
      '<FilesMatch "\.(sql|md|log|zip|ini)$">' \
      '    Require all denied' \
      '</FilesMatch>' \
      '<Files "error_log">' \
      '    Require all denied' \
      '</Files>' \
      'ServerTokens Prod' \
      'ServerSignature Off' \
      > /etc/apache2/conf-available/z-briosa.conf; \
    a2enconf z-briosa

# ---------- aplicação ----------
COPY --chown=www-data:www-data public_html/public_html/ /var/www/html/

USER www-data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD curl -fsS http://localhost:8080/ || exit 1
