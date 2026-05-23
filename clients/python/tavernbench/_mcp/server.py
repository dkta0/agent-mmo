"""
TavernBench MCP server — wraps Session as a set of MCP tools.

Requires:  pip install tavernbench[mcp]

MCP tools exposed (mirror TOOLS_OPENAI names 1-for-1):
    move, look, speak, reply, examine, pickup, drop, use,
    attack, flee, inventory, quests, wait

Resource exposed:
    tavernbench://state  — current session.state as JSON

Transport:
    "stdio"  — mcp.server.stdio.stdio_server  (default; works with Claude Desktop)
    "sse"    — mcp.server.sse.SseServerTransport (HTTP; port from TAVERNBENCH_MCP_PORT env)
"""

import asyncio
import json
import os
import signal
from typing import Any


def run_server(*, api_key: str, server: str, zone: str, transport: str) -> None:
    """
    Wrap the TavernBench Session as MCP tools and serve.

    Session lifecycle:
    - Open Session on first tool call (lazy connect) so `tavernbench mcp`
      can start before the API key is exercised.
    - On SIGINT / SIGTERM: call session.close() then exit.

    Error handling:
    - ActionError from session.call() -> return as MCP tool error (isError=True)
    - AuthError -> fatal, log and exit(1)
    """
    from mcp.server import Server
    from mcp.server.models import InitializationOptions
    import mcp.types as types
    from tavernbench import Session, ActionError, AuthError

    _session: Session | None = None

    async def _get_session() -> Session:
        nonlocal _session
        if _session is None:
            _session = Session(api_key=api_key, server=server, zone=zone)
            await _session.connect()
        return _session

    mcp_server = Server("tavernbench")

    # Tool list mirrors TOOLS_OPENAI action names
    ACTION_TOOLS = [
        "move", "look", "speak", "reply", "examine",
        "pickup", "drop", "use", "attack", "flee",
        "inventory", "quests", "wait",
    ]

    @mcp_server.list_tools()
    async def list_tools() -> list[types.Tool]:
        return [
            types.Tool(
                name=name,
                description=f"TavernBench action: {name}",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "args": {
                            "type": "object",
                            "description": f"Arguments for the {name} action",
                        }
                    },
                    "required": [],
                },
            )
            for name in ACTION_TOOLS
        ]

    @mcp_server.call_tool()
    async def call_tool(name: str, arguments: dict[str, Any]) -> list[types.TextContent]:
        try:
            session = await _get_session()
            result = await session.call(name, **(arguments.get("args") or {}))
            return [types.TextContent(type="text", text=json.dumps(result))]
        except AuthError as e:
            import sys
            print(f"AuthError: {e}", file=sys.stderr)
            raise SystemExit(1)
        except ActionError as e:
            return [types.TextContent(type="text", text=f"Error: {e}")]

    @mcp_server.list_resources()
    async def list_resources() -> list[types.Resource]:
        return [
            types.Resource(
                uri="tavernbench://state",  # type: ignore[arg-type]
                name="TavernBench Session State",
                description="Current session state as JSON",
                mimeType="application/json",
            )
        ]

    @mcp_server.read_resource()
    async def read_resource(uri: Any) -> str:
        session = await _get_session()
        state = session.state
        return json.dumps(state, default=str)

    async def _run_stdio():
        from mcp.server.stdio import stdio_server
        async with stdio_server() as (read_stream, write_stream):
            await mcp_server.run(
                read_stream,
                write_stream,
                InitializationOptions(
                    server_name="tavernbench",
                    server_version="0.1.0",
                    capabilities=mcp_server.get_capabilities(
                        notification_options=None,  # type: ignore[arg-type]
                        experimental_capabilities={},
                    ),
                ),
            )

    async def _run_sse():
        from mcp.server.sse import SseServerTransport
        from starlette.applications import Starlette
        from starlette.routing import Route
        import uvicorn

        port = int(os.environ.get("TAVERNBENCH_MCP_PORT", "8080"))
        sse = SseServerTransport("/messages/")

        async def handle_sse(request: Any):
            async with sse.connect_sse(request.scope, request.receive, request._send) as streams:
                await mcp_server.run(
                    streams[0],
                    streams[1],
                    InitializationOptions(
                        server_name="tavernbench",
                        server_version="0.1.0",
                        capabilities=mcp_server.get_capabilities(
                            notification_options=None,  # type: ignore[arg-type]
                            experimental_capabilities={},
                        ),
                    ),
                )

        starlette_app = Starlette(routes=[Route("/sse", endpoint=handle_sse)])
        config = uvicorn.Config(starlette_app, host="0.0.0.0", port=port)
        uvr = uvicorn.Server(config)
        await uvr.serve()

    async def _main():
        loop = asyncio.get_event_loop()

        def _shutdown():
            if _session is not None:
                loop.create_task(_session.close())
            loop.stop()

        for sig in (signal.SIGINT, signal.SIGTERM):
            try:
                loop.add_signal_handler(sig, _shutdown)
            except NotImplementedError:
                pass  # Windows

        if transport == "sse":
            await _run_sse()
        else:
            await _run_stdio()

    asyncio.run(_main())
