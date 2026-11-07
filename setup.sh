#!/usr/bin/env bash
# =====================================================================
#  First-time server setup (Ubuntu/Debian x86_64)
#    ./setup.sh [--website http://PUBLIC_IP:8080]
#
#  omp-server/ (open.mp + cef.so + compiler) is included in the repo.
#  This script only:
#    - checks the 32-bit runtime open.mp needs
#    - generates an RCON password and sets "website" in config.json
#    - compiles the gamemode
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

WEBSITE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --website) WEBSITE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done
if [[ -z "$WEBSITE" ]]; then
  WEBSITE="http://$(hostname -I | awk '{print $1}'):8080"
  echo "No --website given, using LAN address $WEBSITE"
fi

# ---- 32-bit runtime (open.mp and its components are i386) ----
if [[ ! -e /lib/ld-linux.so.2 ]]; then
  cat <<'MSG'
open.mp needs 32-bit libraries. Run once (needs sudo):
  sudo dpkg --add-architecture i386 && sudo apt update && \
  sudo apt install -y libc6:i386 libstdc++6:i386
MSG
  exit 1
fi

# git on Windows may drop the executable bit
chmod +x omp-server/omp-server omp-server/qawno/pawncc server.sh build-cef-server.sh

# ---- config.json: RCON password (if empty) + website ----
node - "$WEBSITE" <<'JS'
const fs = require("fs"), crypto = require("crypto");
const file = "omp-server/config.json";
const c = JSON.parse(fs.readFileSync(file, "utf8"));
c.rcon = c.rcon || {};
if (!c.rcon.password) {
  c.rcon.password = crypto.randomBytes(12).toString("base64url");
  console.log("config.json: RCON password: " + c.rcon.password + "  (RCON is disabled; enable via rcon.enable)");
}
c.website = process.argv[2];
fs.writeFileSync(file, JSON.stringify(c, null, 4) + "\n");
console.log("config.json: website = " + c.website);
JS

# keep the local password/website out of commits (config.json stays tracked as a template)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git update-index --skip-worktree omp-server/config.json
fi

mkdir -p client-files launcher-releases
./server.sh compile

cat <<MSG

Setup done. Next:
  1. put the client CEF package into client-files/  (built by sa-mp-cef-launcher/build-cef-client.ps1)
  2. open ports: 7777/udp (game), 7779/udp (CEF), 8080/tcp (UI + launcher)
  3. ./server.sh start
MSG
