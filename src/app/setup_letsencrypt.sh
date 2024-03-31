#!/bin/bash

WEBROOT=/var/www/letsencrypt

mkdir -p $WEBROOT

letsencrypt certonly  \
 -m "$LETS_ENCRYPT_CERT_MAIL" \
 --agree-tos \
 --non-interactive \
 $* \
 --webroot -w $WEBROOT -d $APP_DOMAIN

