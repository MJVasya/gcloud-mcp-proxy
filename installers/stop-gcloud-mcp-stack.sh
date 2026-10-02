#!/usr/bin/env bash
# Kill the gcloud MCP proxy + quick-tunnel cloudflared started by start-gcloud-mcp-stack.sh
set -euo pipefail
STATE="${GCLOUD_MCP_STATE:-$HOME/.gcloud-mcp-stack}"
killed=0
for name in proxy.pid cloudflared.pid; do
  f="$STATE/$name"
  if [[ -f "$f" ]]; then
    pid="$(cat "$f")"
    if kill "$pid" 2>/dev/null; then
      echo "killed $name PID=$pid"
      killed=1
    else
      echo "stale $name PID=$pid (already dead)"
    fi
    rm -f "$f"
  fi
done
for p in $(lsof -tiTCP:18783 -sTCP:LISTEN 2>/dev/null || true); do
  echo "killed leftover :18783 PID=$p"
  kill "$p" 2>/dev/null || true
  killed=1
done
for p in $(pgrep -f 'cloudflared tunnel --no-autoupdate --url' || true); do
  echo "killed leftover cloudflared PID=$p"
  kill "$p" 2>/dev/null || true
  killed=1
done
rm -f "$STATE/connector.url"
[[ "$killed" == "1" ]] || echo "nothing running"
echo "state: $STATE"
