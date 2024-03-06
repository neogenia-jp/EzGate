#!/bin/bash

if [ ! -z "$@" ]; then
  exec "$@"
else
  /var/scripts/reload_config.rb
  if [ "$?" != '0' ]; then
    if [ -n "$DEBUG" ]; then
      echo '##### PAUSE (debug mode) #####'
      tail -f /dev/null
    else
      exit 1
    fi
  fi
  logs="/var/log/monit.log /var/log/nginx/*error*.log"

  # start monit
  echo '--- START MONIT -----'
  if [ -z "$MONIT_ARGS" ]; then
    /etc/init.d/monit start
    tail -f $logs
  else
    monit $MONIT_ARGS -I
  fi
fi

