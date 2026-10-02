# gcloud MCP connector

Local proxy in front of `@google-cloud/gcloud-mcp`, exposed with an ephemeral Cloudflare quick tunnel so Grok or Muse can call it over Streamable HTTP.

```text
Grok / Muse -> https://<random>.trycloudflare.com/mcp
            -> gcloud_mcp_proxy.py (127.0.0.1:18783)
            -> npx -y @google-cloud/gcloud-mcp
            -> Google Cloud APIs
```

The URL is new every start and dies when the stack stops. There is no named tunnel, no DNS record, and no account tunnel credential in this repo.

Destructive tools hidden by the proxy: `delete_backup`, `delete_backup_plan`, `delete_backup_plan_association`, `delete_backup_vault`, `delete_bucket`, `delete_object`, `move_object`. Override with `GCLOUD_MCP_DENY` (empty = deny nothing).

## Install

```bash
bash installers/install-gcloud-mcp.sh
```

## Daily

```bash
bash installers/start-gcloud-mcp-stack.sh   # prints the connector URL
bash installers/stop-gcloud-mcp-stack.sh
```

Paste the printed URL into Grok (custom Streamable HTTP connector) or Muse. Treat that URL like a password for the session. The `/mcp` endpoint has no auth of its own.

State (venv, logs, PIDs) stays in `~/.gcloud-mcp-stack` and is not committed.
