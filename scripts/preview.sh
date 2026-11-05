#!/usr/bin/env bash
# Browser preview of the app with live reload (runs in WSL; open http://localhost:8080 in Chrome).
#
#   bash scripts/preview.sh start    # first time / after adding packages (about 1-2 minutes)
#   bash scripts/preview.sh reload   # show code changes in the browser (a few seconds)
#   bash scripts/preview.sh restart  # full restart of the app (keeps the browser tab)
#   bash scripts/preview.sh stop
#
# The code is copied to ~/mb_web so the Windows checkout's .dart_tool is not touched.
set -e
API_URL="${API_URL:-https://micro-bargain-api.onrender.com/api/v1}"
SRC="$(cd "$(dirname "$0")/../mobile" && pwd)"
DEST="$HOME/mb_web"
PID_FILE=/tmp/mb_preview.pid
LOG=/tmp/mb_preview.log
FLUTTER="$HOME/flutter/bin/flutter"

sync() {
  mkdir -p "$DEST"
  rsync -a --delete --exclude build --exclude .dart_tool --exclude android --exclude ios "$SRC/" "$DEST/"
}

running() { [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; }

case "${1:-start}" in
  start)
    if running; then echo "Preview already running: http://localhost:8080"; exit 0; fi
    sync
    cd "$DEST"
    "$FLUTTER" pub get >/dev/null
    rm -f "$PID_FILE"
    nohup "$FLUTTER" run -d web-server --web-hostname 0.0.0.0 --web-port 8080 \
      --dart-define=API_BASE_URL="$API_URL" --pid-file "$PID_FILE" < /dev/null > "$LOG" 2>&1 &
    for _ in $(seq 1 120); do
      grep -q "is being served at" "$LOG" 2>/dev/null && { echo "PREVIEW_READY http://localhost:8080"; exit 0; }
      grep -qiE "^Error|failed to compile|Compilation failed" "$LOG" 2>/dev/null && { tail -30 "$LOG"; exit 1; }
      sleep 2
    done
    echo "Still starting; see $LOG"; tail -15 "$LOG"
    ;;
  reload|restart)
    running || { echo "Preview not running; use: start"; exit 1; }
    sync
    before=$(wc -l < "$LOG")
    if [ "$1" = reload ]; then kill -USR1 "$(cat "$PID_FILE")"; else kill -USR2 "$(cat "$PID_FILE")"; fi
    for _ in $(seq 1 60); do
      new=$(tail -n +"$((before + 1))" "$LOG")
      echo "$new" | grep -qiE "Reloaded|Restarted|Recompile complete" && { echo "$new" | tail -3; echo "DONE: refresh not needed"; exit 0; }
      echo "$new" | grep -qiE "error" && { echo "$new" | tail -30; exit 1; }
      sleep 1
    done
    echo "No confirmation yet:"; tail -10 "$LOG"
    ;;
  stop)
    running && kill "$(cat "$PID_FILE")" && echo stopped || echo "not running"
    ;;
  log) tail -40 "$LOG" ;;
esac
