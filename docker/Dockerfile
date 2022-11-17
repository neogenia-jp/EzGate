FROM ubuntu:focal-20210217

LABEL Vendor     "Neogenia Ltd."
LABEL maintainer "WATARU MAEDA <w.maeda@neogenia.co.jp>"

ENV DEBIAN_FRONTEND=noninteractive

############################################################
# timezone, lang settings
ENV LANG=C.UTF-8
#RUN ln -sf /usr/share/zoneinfo/Japan /etc/localtime

############################################################
# install nginx
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
        less vim-tiny \
 && apt-get clean \
 && rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*

############################################################
# nginx settings
ADD resources/nginx/etc/nginx/nginx.conf /etc/nginx/

############################################################
# monit settings
ADD resources/monit/* /etc/monit/conf.d/

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

ADD resources/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 700 /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 80 443

#####################################################
# copy script files
ADD resources/scripts /var/scripts
RUN chmod 700 /var/scripts/*

RUN mkdir /var/www/letsencrypt
