ARG UBUNTU_VERSION=noble-20260210.1

FROM ubuntu:$UBUNTU_VERSION AS base

LABEL Vendor="Neogenia Ltd."
LABEL maintainer="WATARU MAEDA <w.maeda@neogenia.co.jp>"

ENV DEBIAN_FRONTEND=noninteractive

############################################################
# timezone, lang settings
ENV LANG=C.UTF-8
#RUN ln -sf /usr/share/zoneinfo/Japan /etc/localtime

############################################################
# install nginx, and depends packages
#
# nginx は Ubuntu 標準の apt ではなく、nginx.org の公式 apt リポジトリ (stable) から入れる。
# NGINX_VERSION は build.sh が自動判定して渡す。(例: 1.30.7-1~noble)
ARG NGINX_VERSION
RUN test -n "$NGINX_VERSION" || { echo "ERROR: --build-arg NGINX_VERSION=<version> is required (use build.sh)" >&2; exit 1; }

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl gnupg ca-certificates \
 && curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg \
 && gpg --show-keys --with-colons /usr/share/keyrings/nginx-archive-keyring.gpg | grep -q '^fpr:::::::::573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62:' \
 && echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/ubuntu $(. /etc/os-release; echo $VERSION_CODENAME) nginx" > /etc/apt/sources.list.d/nginx.list \
 && printf 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n' > /etc/apt/preferences.d/99nginx \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
        monit cron \
        apache2-utils \
        nginx=$NGINX_VERSION \
        openssl \
        locales tzdata \
        letsencrypt \
        logrotate \
        ruby \
        socat \
        less vim-tiny \
 && apt-get clean \
 && rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*

# nginx.org 版のパッケージには sites-enabled が無く、conf.d/default.conf (80番のデフォルトサーバ) が入っているため、
# Ubuntu 版と同じ構成 (sites-enabled に EzGate が設定を出力する) に合わせる
RUN mkdir -p /etc/nginx/sites-enabled \
 && rm -f /etc/nginx/conf.d/default.conf

############################################################
# nginx settings
COPY docker.resources/nginx/etc/nginx/nginx.conf /etc/nginx/

############################################################
# monit settings
COPY docker.resources/monit/* /etc/monit/conf.d/

############################################################
# add 'reload nginx' into setting of cron
RUN sed -i -e "s|q renew|q renew --deploy-hook '/usr/sbin/service nginx reload'|g" \
              /etc/cron.d/certbot

############################################################
# logrotate settings
# https://ito-u-oti.com/docker-nginx-logrotate/
RUN rm /etc/cron.daily/dpkg \
       /etc/cron.daily/apt-compat
RUN sed -i -e "s|^/var/log/nginx/\*.log|/var/log/nginx/access.log /var/log/nginx/error.log|" \
              /etc/logrotate.d/nginx

COPY docker.resources/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 700 /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 80 443

RUN mkdir -p /var/www/letsencrypt

RUN gem install bundler

#####################################################
# copy script files
WORKDIR /var/scripts
COPY src ./
RUN chmod 744 ./reload_config.*
RUN mkdir -p /var/log/ezgate

RUN bundle install



FROM base AS tester
RUN bin/rake test



FROM base AS openappsec-install

############################################################
# install open-appsec attachment module for nginx
# binutils: インストーラが nginx バイナリの署名 (strings) を調べるために必要
RUN apt-get update && apt-get install -y --no-install-recommends binutils \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp
RUN curl https://downloads.openappsec.io/open-appsec-install -O
RUN chmod +x open-appsec-install
RUN ./open-appsec-install --download
RUN mkdir -p /outlet
RUN mv open-appsec/ngx_module_*/* /outlet/  # ngx_module_1.30.4-1-noble/ のようなディレクトリの中身を出力用ディレクトリに移動



FROM base AS openappsec

COPY --from=openappsec-install /outlet/libosrc_shmem_ipc.so             /usr/lib/
COPY --from=openappsec-install /outlet/libosrc_compression_utils.so     /usr/lib/
COPY --from=openappsec-install /outlet/libosrc_nginx_attachment_util.so /usr/lib/
COPY --from=openappsec-install /outlet/libshmem_ipc_2.so /usr/lib/
RUN mkdir -p /usr/lib/nginx/modules/
COPY --from=openappsec-install /outlet/ngx_cp_attachment_module.so      /usr/lib/nginx/modules/

# nginx コンフィグに open-appsec モジュールのロードを追記
RUN sed -i '1i load_module /usr/lib/nginx/modules/ngx_cp_attachment_module.so;' /etc/nginx/nginx.conf

