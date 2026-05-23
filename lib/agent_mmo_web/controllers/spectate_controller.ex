defmodule AgentMmoWeb.SpectateController do
  use AgentMmoWeb, :controller

  @moduledoc """
  Serves:
    GET /spectate           — embeddable iframe HTML with live JS widget
    GET /api/spectate/current  — JSON snapshot of current top ranked run
    GET /api/spectate/ranked   — JSON list of all active ranked runs
  """

  def embed(conn, _params) do
    html = spectate_html(get_ws_url(conn))

    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> put_resp_header("x-frame-options", "ALLOWALL")
    |> put_resp_header("content-security-policy", "frame-ancestors *")
    |> send_resp(200, html)
  end

  def current(conn, _params) do
    run = AgentMmo.SpectateTracker.current_run()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    conn
    |> put_status(200)
    |> json(%{current_run: run, generated_at: now})
  end

  def ranked(conn, params) do
    limit =
      case Integer.parse(Map.get(params, "limit", "10")) do
        {n, _} -> min(n, 20)
        :error -> 10
      end

    runs = AgentMmo.SpectateTracker.ranked_runs(limit)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    conn
    |> put_status(200)
    |> json(%{runs: runs, generated_at: now})
  end

  # Build absolute WS URL from the current request host
  defp get_ws_url(conn) do
    scheme = if conn.scheme == :https, do: "wss", else: "ws"
    host = conn.host
    port = conn.port

    default_port = if conn.scheme == :https, do: 443, else: 80

    if port == default_port do
      "#{scheme}://#{host}/spectator_socket"
    else
      "#{scheme}://#{host}:#{port}/spectator_socket"
    end
  end

  defp spectate_html(ws_url) do
    ~S"""
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Agent MMO — Live Run</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #0a0a0f;
      color: #e2e8f0;
      font-family: 'Courier New', monospace;
      height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      overflow: hidden;
    }
    #widget {
      width: 100%;
      max-width: 560px;
      padding: 20px;
    }
    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 12px;
    }
    .title {
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 2px;
      color: #64748b;
    }
    .live-dot {
      width: 7px;
      height: 7px;
      border-radius: 50%;
      background: #22c55e;
      animation: pulse 1.5s ease-in-out infinite;
    }
    .live-dot.offline { background: #475569; animation: none; }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.3; }
    }
    .agent-name {
      font-size: 22px;
      font-weight: bold;
      color: #f8fafc;
      margin-bottom: 4px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .scenario {
      font-size: 12px;
      color: #94a3b8;
      margin-bottom: 16px;
    }
    .stats {
      display: grid;
      grid-template-columns: 1fr 1fr 1fr;
      gap: 12px;
      margin-bottom: 16px;
    }
    .stat {
      background: #1e293b;
      border: 1px solid #334155;
      border-radius: 8px;
      padding: 10px 14px;
    }
    .stat-label {
      font-size: 10px;
      text-transform: uppercase;
      letter-spacing: 1px;
      color: #64748b;
      margin-bottom: 4px;
    }
    .stat-value {
      font-size: 20px;
      font-weight: bold;
      color: #38bdf8;
    }
    .zone-bar {
      background: #1e293b;
      border: 1px solid #334155;
      border-radius: 8px;
      padding: 8px 14px;
      font-size: 12px;
      color: #94a3b8;
    }
    .zone-bar span { color: #e2e8f0; }
    .no-run {
      text-align: center;
      padding: 40px 20px;
      color: #475569;
      font-size: 13px;
    }
    .no-run .icon { font-size: 32px; margin-bottom: 12px; }
    .footer {
      margin-top: 14px;
      text-align: right;
      font-size: 10px;
      color: #334155;
    }
  </style>
</head>
<body>
  <div id="widget">
    <div class="header">
      <div class="title">Agent MMO &mdash; Live Run</div>
      <div class="live-dot offline" id="dot"></div>
    </div>
    <div id="content">
      <div class="no-run">
        <div class="icon">⏳</div>
        Connecting…
      </div>
    </div>
    <div class="footer" id="footer"></div>
  </div>

  <script>
    const WS_URL = "WS_URL_PLACEHOLDER";
    const RECONNECT_MS = 3000;
    let sock = null;

    function renderRun(run) {
      if (!run) {
        return `<div class="no-run"><div class="icon">🎮</div>No active runs right now</div>`;
      }
      return `
        <div class="agent-name">${esc(run.agent_name || run.player_id)}</div>
        <div class="scenario">Scenario: ${esc(run.scenario || '—')}</div>
        <div class="stats">
          <div class="stat">
            <div class="stat-label">Score</div>
            <div class="stat-value" id="s-score">${run.score ?? '—'}</div>
          </div>
          <div class="stat">
            <div class="stat-label">Steps</div>
            <div class="stat-value" id="s-steps">${run.steps ?? '—'}</div>
          </div>
          <div class="stat">
            <div class="stat-label">Zone</div>
            <div class="stat-value" style="font-size:13px" id="s-zone">${esc(run.zone_id || '—')}</div>
          </div>
        </div>
        <div class="zone-bar">Started: <span>${esc(run.started_at || '—')}</span></div>
      `;
    }

    function updateRun(run) {
      const scoreEl = document.getElementById('s-score');
      const stepsEl = document.getElementById('s-steps');
      const zoneEl  = document.getElementById('s-zone');
      if (scoreEl && run) {
        scoreEl.textContent = run.score ?? '—';
        stepsEl.textContent = run.steps ?? '—';
        zoneEl.textContent  = run.zone_id || '—';
      } else {
        document.getElementById('content').innerHTML = renderRun(run);
      }
    }

    function esc(s) {
      const d = document.createElement('div');
      d.textContent = String(s);
      return d.innerHTML;
    }

    function setDot(live) {
      const d = document.getElementById('dot');
      d.className = 'live-dot' + (live ? '' : ' offline');
    }

    function footer(msg) {
      document.getElementById('footer').textContent = msg;
    }

    function connect() {
      const ws = new WebSocket(WS_URL + "/websocket");
      sock = ws;

      const joinMsg = [null, "1", "spectate:lobby", "phx_join", {}];

      ws.onopen = () => {
        setDot(true);
        footer('');
        ws.send(JSON.stringify(joinMsg));
      };

      ws.onmessage = (evt) => {
        let msg;
        try { msg = JSON.parse(evt.data); } catch { return; }
        const [, , , event, payload] = msg;

        if (event === "phx_reply" && payload.status === "ok") {
          // Initial join response — render current_run from response
          const run = payload.response && payload.response.current_run;
          document.getElementById('content').innerHTML = renderRun(run || null);
          footer('Connected · ' + new Date().toLocaleTimeString());
        }

        if (event === "current_run") {
          updateRun(payload.run);
          footer('Updated · ' + new Date().toLocaleTimeString());
        }
      };

      ws.onerror = () => {
        setDot(false);
        footer('Connection error');
      };

      ws.onclose = () => {
        setDot(false);
        footer('Reconnecting…');
        setTimeout(connect, RECONNECT_MS);
      };

      // Phoenix heartbeat every 30s
      setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify([null, "hb", "phoenix", "heartbeat", {}]));
        }
      }, 30000);
    }

    connect();
  </script>
</body>
</html>
""" |> String.replace("WS_URL_PLACEHOLDER", ws_url)
  end
end
