"""
TavernBench CLI — entry point for `tavernbench` binary.

Install with:  pip install tavernbench[cli]
               uv tool install "tavernbench[cli]"
"""

import typer
from typing import Optional

app = typer.Typer(name="tavernbench", help="TavernBench SDK CLI — evaluate AI agents in a DnD dungeon crawler")


@app.command()
def version():
    """Print SDK version."""
    from tavernbench import __version__
    typer.echo(__version__)


@app.command()
def play(
    api_key: str = typer.Option(..., envvar="TAVERNBENCH_API_KEY", help="TavernBench API key"),
    server: str = typer.Option("ws://tavernbench.dkta.dev:4100", envvar="TAVERNBENCH_SERVER", help="WebSocket server URL"),
    zone: str = typer.Option("lobby", help="Starting zone"),
):
    """(Placeholder) Interactive spectator / manual play loop."""
    typer.echo("play not yet implemented")


@app.command()
def mcp(
    api_key: str = typer.Option(..., envvar="TAVERNBENCH_API_KEY", help="TavernBench API key"),
    server: str = typer.Option("ws://tavernbench.dkta.dev:4100", envvar="TAVERNBENCH_SERVER", help="WebSocket server URL"),
    zone: str = typer.Option("lobby", help="Starting zone"),
    transport: str = typer.Option("stdio", help="Transport mode: stdio or sse"),
):
    """Start the TavernBench MCP server."""
    try:
        from tavernbench._mcp.server import run_server
    except ImportError:
        typer.echo("mcp extra not installed. Run: pip install tavernbench[mcp]", err=True)
        raise typer.Exit(1)
    run_server(api_key=api_key, server=server, zone=zone, transport=transport)


@app.command()
def doctor(
    server: str = typer.Option(
        "ws://localhost:4100",
        envvar="TAVERNBENCH_SERVER",
        help="WebSocket server URL (ws:// or wss://)",
    ),
    api_key: str = typer.Option(
        "",
        envvar="TAVERNBENCH_API_KEY",
        help="API key to validate",
    ),
):
    """Check server reachability, API key validity, and MCP registration."""
    from tavernbench.doctor import (
        check_server_reachable,
        check_api_key,
        check_mcp_registration,
        PASS, FAIL, WARN, SKIP, GREEN, RED, YELLOW, RESET,
    )

    typer.echo(f"\ntavernbench doctor  {server}\n")

    all_ok = True

    ok, detail = check_server_reachable(server)
    label = "server reachable"
    status = PASS if ok else FAIL
    typer.echo(f"  [{status}] {label}  — {detail}")
    if not ok:
        all_ok = False

    ok, detail = check_api_key(server, api_key or None)
    label = "api key valid"
    status = PASS if ok else FAIL
    typer.echo(f"  [{status}] {label}  — {detail}")
    if not ok:
        all_ok = False

    mcp_results = check_mcp_registration()
    if not mcp_results:
        typer.echo(f"  [{SKIP}] MCP registration  — No MCP-capable clients detected on this machine")
    else:
        mcp_any_ok = False
        for client_name, found, cfg_path in mcp_results:
            status = PASS if found else WARN
            if found:
                mcp_any_ok = True
            typer.echo(f"  [{status}] MCP: {client_name}  — {cfg_path}")
        if not mcp_any_ok:
            typer.echo(
                f"\n  hint: Add tavernbench to an MCP client config to use it as a tool.\n"
                f"  Example entry for claude_desktop_config.json:\n"
                f'    "tavernbench": {{"command": "tavernbench-mcp"}}'
            )

    typer.echo("")
    if all_ok:
        typer.echo("All checks passed.")
        raise typer.Exit(0)
    else:
        typer.echo("Some checks failed.  Fix the issues above and re-run.")
        raise typer.Exit(1)


def main():
    app()
