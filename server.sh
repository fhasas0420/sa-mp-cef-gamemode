#!/usr/bin/env bash
# Usage: ./server.sh start|stop|restart|status|compile
# Manages the open.mp game server (screen: fr-game) and update server (screen: fr-web).
cd "$(dirname "$0")"
ROOT="$PWD"

stop_proc() { # $1 = pgrep pattern, $2 = screen name
  screen -S "$2" -X quit 2>/dev/null
  pkill -TERM -f "$1" 2>/dev/null
  for _ in $(seq 20); do pgrep -f "$1" >/dev/null || return 0; sleep 0.5; done
  pkill -KILL -f "$1" 2>/dev/null; sleep 0.5
}

compile() {
  cd "$ROOT/omp-server/qawno" && LD_LIBRARY_PATH=. ./pawncc ../gamemodes/freeroam.pwn -i./include \
    -o../gamemodes/freeroam.amx -d1 -O1 '-;+' '-(+' 2>&1 | grep -vE "^Pawn compiler|^$"
  local rc=${PIPESTATUS[0]}; cd "$ROOT"
  [ "$rc" = 0 ] && echo "compiled OK" || { echo "COMPILE FAILED"; return 1; }
}

start() {
  pgrep -f "^\./omp-server$" >/dev/null || screen -dmS fr-game bash -c "cd '$ROOT/omp-server' && exec ./omp-server >> console.log 2>&1"
  pgrep -f "node server.js" >/dev/null || screen -dmS fr-web bash -c "cd '$ROOT/update-server' && exec node server.js >> server.log 2>&1"
  # wait (max 10s) until the CEF port is bound and the web server answers
  for _ in $(seq 20); do
    ss -lun 2>/dev/null | grep -qE ":7779\b" && curl -s -o /dev/null localhost:8080/ && break
    sleep 0.5
  done
  status
}

stop() { stop_proc "^\./omp-server$" fr-game; stop_proc "node server.js" fr-web; echo "stopped"; }

status() {
  pgrep -af "^\./omp-server$" >/dev/null && echo "game:   running" || echo "game:   STOPPED"
  pgrep -af "node server.js"  >/dev/null && echo "web:    running" || echo "web:    STOPPED"
  ss -lunpt 2>/dev/null | grep -qE ":7779\b" && echo "cef:    listening on 7779" || echo "cef:    NOT listening"
}

case "$1" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  status) status ;;
  compile) compile ;;
  rebuild) compile && { stop_proc "^\./omp-server$" fr-game; start; } ;;
  *) echo "Usage: $0 start|stop|restart|status|compile|rebuild" ;;
esac
