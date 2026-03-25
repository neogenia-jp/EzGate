#!/bin/bash

if [ ! -z "$@" ]; then
  exec "$@"
else
  logs="/var/log/monit.log /var/log/nginx/*error*.log"
  reload_log="/var/log/ezgate/reload_config.log"

  # start monit
  echo '--- START MONIT -----'
  if [ -z "$MONIT_ARGS" ]; then
    /etc/init.d/monit start
  else
    # MONIT_ARGS 指定時は出力をファイルにリダイレクト
    monit $MONIT_ARGS -I > /var/log/monit.log 2>&1 &
    MONIT_PID=$!
  fi

  # run reload_config
  /var/scripts/reload_config.sh
  if [ "$?" != '0' ]; then
    if [ -n "$DEBUG" ]; then
      echo '##### PAUSE (debug mode) #####'
      tail -f /dev/null
    else
      exit 1
    fi
  fi

  # tail both monit log and reload_config log
  logs="$logs $reload_log"
  tail -f $logs
fi

