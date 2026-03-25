#!/bin/bash
SCRIPT_DIR=$(cd $(dirname $0) && pwd)

LOGFILE="/var/log/ezgate/reload_config.log"
mkdir -p "$(dirname "$LOGFILE")"

# -q 付きで呼び出された場合はファイルのみ出力
if [ "$1" = "-q" ]; then
  "$SCRIPT_DIR/reload_config.rb" >> "$LOGFILE" 2>&1
else
  # 通常時は tee で stdout とファイル両方に出力
  "$SCRIPT_DIR/reload_config.rb" 2>&1 | tee -a "$LOGFILE"
fi
