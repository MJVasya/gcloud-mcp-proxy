#!/usr/bin/env python3
"""Public HTTP gateway for the official gcloud MCP server.

Grok / Muse (custom connectors) -> https://<tunnel-host>/mcp   (Streamable HTTP)
    -> this proxy (127.0.0.1:18783, denylist enforced here)
    -> npx -y @google-cloud/gcloud-mcp                          (stdio, your gcloud auth)
    -> Google Cloud APIs

The denylist implements the PolicyLayer precheck verdict for
@google-cloud/gcloud-mcp (connect-with-rule): the 7 destructive tools are
hidden from tools/list AND rejected on direct call, because Grok/Muse
connectors cannot enforce client-side deny rules.
Override with GCLOUD_MCP_DENY (comma-separated, empty = deny nothing).
"""

from __future__ import annotations

import argparse
import os
import sys

# Set before importing fastmcp: settings are read at import time. A long-running
# gateway should not phone PyPI on every start.
os.environ.setdefault("FASTMCP_CHECK_FOR_UPDATES", "off")

from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from fastmcp.exceptions import ToolError
from fastmcp.server.middleware import Middleware, MiddlewareContext
from fastmcp.server.providers.proxy import FastMCPProxy

DEFAULT_LISTEN = "127.0.0.1"
DEFAULT_PORT = 18783

# PolicyLayer precheck 2026-10-02: "publisher unverified with 7 destructive
# tool(s) exposed" -> suggested action connect-with-rule. Record:
# https://policylayer.com/tools/gcloud
DEFAULT_DENY = {
    "delete_backup",
    "delete_backup_plan",
    "delete_backup_plan_association",
    "delete_backup_vault",
    "delete_bucket",
    "delete_object",
    "move_object",
}


def denied_tools() -> set[str]:
    raw = os.environ.get("GCLOUD_MCP_DENY")
    if raw is None:
        return set(DEFAULT_DENY)
    return {t.strip() for t in raw.split(",") if t.strip()}


class DenyListMiddleware(Middleware):
    def __init__(self, denied: set[str]):
        self.denied = denied

    async def on_list_tools(self, context: MiddlewareContext, call_next):
        tools = await call_next(context)
        return [t for t in tools if t.name not in self.denied]

    async def on_call_tool(self, context: MiddlewareContext, call_next):
        name = context.message.name
        if name in self.denied:
            raise ToolError(f"tool '{name}' is denied by proxy policy")
        return await call_next(context)


def make_client() -> Client:
    return Client(
        transport=StdioTransport(
            command="npx",
            args=["-y", "@google-cloud/gcloud-mcp"],
        )
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--listen", default=os.environ.get("BRIDGE_LISTEN", DEFAULT_LISTEN))
    ap.add_argument("--port", type=int,
                    default=int(os.environ.get("BRIDGE_PORT", DEFAULT_PORT)))
    args = ap.parse_args()

    denied = denied_tools()
    proxy = FastMCPProxy(
        client_factory=make_client,
        name="gcloud-mcp",
        instructions=(
            "Google Cloud via the official gcloud MCP server. "
            "Destructive tools (bucket/object/backup deletion) are disabled by proxy policy."
        ),
    )
    proxy.add_middleware(DenyListMiddleware(denied))
    sys.stderr.write(f"gcloud-mcp proxy: denied tools: {sorted(denied) or 'none'}\n")
    sys.stderr.flush()
    proxy.run(
        transport="streamable-http",
        show_banner=False,
        host=args.listen,
        port=args.port,
        path="/mcp",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
