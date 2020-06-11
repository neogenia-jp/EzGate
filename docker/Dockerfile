FROM ubuntu:bionic-20180224

LABEL Vendor     "Neogenia Ltd."
LABEL maintainer "WATARU MAEDA <w.maeda@neogenia.co.jp>"

ENV DEBIAN_FRONTEND=noninteractive

############################################################
# timezone, lang settings
ENV LANG=C.UTF-8
#RUN ln -sf /usr/share/zoneinfo/Japan /etc/localtime

############################################################
# install nginx
RUN apt-get update && apt-get install -y --no-install-recommends \
        monit cron \
        apache2-utils \
        nginx \
        openssl \
        locales tzdata \
        letsencrypt \
        ruby \
        less vim-tiny

############################################################
# nginx settings
ADD resources/nginx/etc/nginx/nginx.conf /etc/nginx/

############################################################
# monit settings
ADD resources/monit/* /etc/monit/conf.d/

############################################################
# cron settings
ADD resources/crond/* /etc/cron.d/
RUN chmod 0644 /etc/cron.d/*
# take over env_vars for cron jobs
RUN env |sed 's/^\(.*\)$/export \1/g' >>/root/.profile

############################################################
# clean apt-get files
RUN apt-get clean && rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*

ADD resources/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 700 /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 80 443

#####################################################
# copy script files
ADD resources/scripts /var/scripts
RUN chmod 700 /var/scripts/*
