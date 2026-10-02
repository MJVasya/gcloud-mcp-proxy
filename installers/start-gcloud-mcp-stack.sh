#!/usr/bin/env bash
# Daily stack: gcloud MCP proxy + ephemeral Cloudflare quick tunnel.
# One-time first: installers/install-gcloud-mcp.sh
# Prints a new https://<random>.trycloudflare.com/mcp URL each start.
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Do not use sudo. Run as your login user."
  exit 1
fi

LISTEN="${BRIDGE_LISTEN:-127.0.0.1}"
PORT="${BRIDGE_PORT:-18783}"
WAIT_SECS="${TUNNEL_WAIT:-30}"
STATE="${GCLOUD_MCP_STATE:-$HOME/.gcloud-mcp-stack}"
mkdir -p "$STATE"
VENV_PY="$STATE/venv/bin/python"
LOG="$STATE/cloudflared.log"
URL_FILE="$STATE/connector.url"
PID_PROXY="$STATE/proxy.pid"
PID_CF="$STATE/cloudflared.pid"

[[ -x "$VENV_PY" ]] || {
  echo "missing venv at $STATE/venv"
  echo "run first: bash installers/install-gcloud-mcp.sh"
  exit 1
}

resolve_proxy() {
  local SOURCE DIR ROOT c
  SOURCE="${BASH_SOURCE[0]}"
  while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="${DIR}/${SOURCE}"
  done
  SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
  for c in \
    "${GCLOUD_MCP_LIBEXEC:-}/bridge/gcloud_mcp_proxy.py" \
    "${ROOT}/bridge/gcloud_mcp_proxy.py"
  do
    [[ -n "${c}" && -f "$c" ]] && echo "$c" && return 0
  done
  return 1
}

stop_old() {
  for f in "$PID_PROXY" "$PID_CF"; do
    if [[ -f "$f" ]]; then
      kill "$(cat "$f")" 2>/dev/null || true
      rm -f "$f"
    fi
  done
}

PROXY="$(resolve_proxy)" || {
  echo "missing gcloud_mcp_proxy.py"
  exit 1
}
command -v cloudflared >/dev/null || {
  echo "install cloudflared: brew install cloudflare/cloudflare/cloudflared"
  exit 1
}

stop_old
: > "$LOG"
rm -f "$URL_FILE"

"$VENV_PY" "$PROXY" --listen "$LISTEN" --port "$PORT" \
  >"$STATE/proxy.log" 2>&1 &
echo $! > "$PID_PROXY"
sleep 1
if ! kill -0 "$(cat "$PID_PROXY")" 2>/dev/null; then
  echo "proxy failed to start"; tail -n 20 "$STATE/proxy.log"; exit 1
fi

# Quick tunnel: no account tunnel, no DNS, new hostname every start.
nohup cloudflared tunnel --no-autoupdate --url "http://${LISTEN}:${PORT}" \
  >"$LOG" 2>&1 &
echo $! > "$PID_CF"

echo "Waiting up to ${WAIT_SECS}s for a quick-tunnel URL..."
URL=""
for _ in $(seq 1 "$WAIT_SECS"); do
  URL="$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$LOG" 2>/dev/null | head -n 1 || true)"
  [[ -n "$URL" ]] && break
  sleep 1
done
if [[ -z "$URL" ]]; then
  echo "FAIL: no trycloudflare.com URL in $LOG"
  tail -n 20 "$LOG"
  exit 1
fi

URL="${URL}/mcp"
printf '%s\n' "$URL" > "$URL_FILE"
printf 'CONNECTOR_URL=%s\n' "$URL"
echo "$URL" | pbcopy 2>/dev/null || true
echo "Paste once per session: Grok -> grok.com/connectors -> New Connector -> Custom (Streamable HTTP)"
echo "                        Muse -> app Settings -> Connectors -> Add custom connector"
echo "This URL dies when the stack stops. Stop: bash installers/stop-gcloud-mcp-stack.sh"
echo "PIDs: proxy=$(cat "$PID_PROXY") cloudflared=$(cat "$PID_CF")"
