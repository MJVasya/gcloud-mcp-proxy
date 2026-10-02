#!/usr/bin/env bash
# One-time install for the gcloud MCP connector.
# Checks: python3, node >= 20 (npx), gcloud CLI, cloudflared. Creates a venv
# and installs the proxy's Python deps. Run on the machine whose gcloud auth
# you want to expose. Daily access uses an ephemeral Cloudflare quick tunnel.
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Do not use sudo. Run as your login user."
  exit 1
fi

STATE="${GCLOUD_MCP_STATE:-$HOME/.gcloud-mcp-stack}"

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

command -v python3 >/dev/null || { echo "FAIL: python3 required"; exit 1; }
command -v node >/dev/null || { echo "FAIL: node required (https://nodejs.org, v20+)"; exit 1; }
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[[ "$NODE_MAJOR" -ge 20 ]] || { echo "FAIL: node >= 20 required (found $NODE_MAJOR)"; exit 1; }
command -v npx >/dev/null || { echo "FAIL: npx required (ships with node)"; exit 1; }
command -v gcloud >/dev/null || {
  echo "FAIL: gcloud CLI required (https://cloud.google.com/sdk/docs/install)"
  echo "      then: gcloud auth login"
  exit 1
}
if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q .; then
  echo "WARN: no active gcloud account found. Run: gcloud auth login"
fi
command -v cloudflared >/dev/null || {
  echo "FAIL: cloudflared required for the quick tunnel."
  echo "      macOS: brew install cloudflare/cloudflare/cloudflared"
  exit 1
}

mkdir -p "$STATE"
if [[ ! -x "$STATE/venv/bin/python" ]]; then
  echo "creating venv at $STATE/venv"
  python3 -m venv "$STATE/venv"
fi
echo "installing proxy deps"
"$STATE/venv/bin/pip" install -q --upgrade pip
"$STATE/venv/bin/pip" install -q -r "$ROOT/bridge/requirements.txt"

echo ""
echo "OK. Next: bash installers/start-gcloud-mcp-stack.sh"
echo "Each start prints a new trycloudflare.com URL. Paste that into the connector."
