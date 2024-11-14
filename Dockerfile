FROM ubuntu:noble-20240225 AS base

LABEL Vendor     "Neogenia Ltd."
LABEL maintainer "WATARU MAEDA <w.maeda@neogenia.co.jp>"

ENV DEBIAN_FRONTEND=noninteractive

############################################################
# timezone, lang settings
ENV LANG=C.UTF-8
#RUN ln -sf /usr/share/zoneinfo/Japan /etc/localtime

############################################################
# install nginx, and depends packages
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        monit cron \
        apache2-utils \
        nginx \
        openssl \
        locales tzdata \
        letsencrypt \
        logrotate \
        ruby \
        curl \
        socat \
        less vim-tiny \
 && apt-get clean \
 && rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*

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

RUN mkdir /var/www/letsencrypt

RUN gem install bundler

#####################################################
# copy script files
WORKDIR /var/scripts
COPY src ./
RUN chmod 700 ./reload_config.rb

RUN bundle install

FROM base AS tester
RUN bin/rake test

