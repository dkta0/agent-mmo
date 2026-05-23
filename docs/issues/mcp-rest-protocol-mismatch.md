# Issue: MCP Server Expects REST API That Doesn't Exist

**Severity:** Critical — blocks all e2e agent runs  
**Filed:** 2026-05-23  
**For:** Claude Code planning session

---

## Summary

The MCP server (`tavernbench-client/tavernbench_cli/mcp/server.py`) was written assuming a REST API surface that does not exist in the arena backend. The MCP server's first tool call — `get_world_state` — immediately GETs `/api/scenarios`, which returns **404**. No agent can complete a run.

## Smoke Test Evidence

```
GET https://tavernbench.dkta.dev/api/scenarios  → 404 Not Found
POST https://tavernbench.dkta.dev/api/actions   → 404 Not Found
GET https://tavernbench.dkta.dev/api/leaderboard → 200 OK  ✅ (this one exists)
GET https://tavernbench.dkta.dev/health          → 200 OK  ✅
```

## Root Cause

The arena is WebSocket-first. All game state and actions are exchanged over Phoenix channels:
- Transport: `UserSocket` at `/socket/websocket`  
- Channel topic: `zone:<id>`  
- Join → receive state tick → push action → receive updated tick

The MCP server was built in isolation using `httpx` REST calls. It has no WebSocket client code.

## Failing MCP Tool → Expected Endpoint Mapping

| MCP Tool | Expected endpoint | Arena reality |
|---|---|---|
| `get_world_state` | `GET /api/scenarios` | WebSocket: join `zone:<id>` |
| `send_action` | `POST /api/actions` | WebSocket: push `action` to channel |
| `start_casual_run` | `POST /api/runs` | Needs design |
| `get_leaderboard` | `GET /api/leaderboard` | ✅ exists |
| `confirm_ranked` | `PATCH /api/runs/:id/rank` | Needs design |

## Options

### Option A — Add REST shim endpoints (recommended for MVP)

Add `GET /api/scenarios` and `POST /api/actions` to the Phoenix router. Thin wrappers that:
- `GET /api/scenarios` → reads available scenarios from DB/config, returns JSON list
- `POST /api/actions` → validates API key, dispatches action to the appropriate game channel via `Phoenix.PubSub` or direct GenServer call, returns updated state

**Pros:** No MCP server changes. Fast. Decoupled.  
**Cons:** Extra HTTP round-trip per action; state sync may lag WebSocket.  
**Estimated effort:** ~1 day (2–3 controller actions + tests)

### Option B — Rewrite MCP server to use WebSocket

Replace `httpx` REST calls in `mcp/server.py` with a Phoenix Channels WebSocket client. MCP server:
1. Connects to `ws://arena/socket/websocket`
2. Joins channel `zone:<id>`
3. Receives state push events → maps to MCP tool responses
4. Sends actions via channel push

**Pros:** Correct long-term architecture. Real-time state.  
**Cons:** Requires implementing Phoenix Channels client protocol in Python (or using `phoenixpy`). More complex, harder to test.  
**Estimated effort:** ~2–3 days

### Option C — Hybrid: REST for reads, WebSocket for actions (best UX)

- `GET /api/scenarios`, `GET /api/leaderboard` → REST (already works or easy to add)
- `POST /api/actions` → WebSocket push (real-time, no polling)
- MCP server manages one persistent WebSocket connection per run

**Estimated effort:** ~2–3 days

## Recommendation

**Start with Option A** to unblock the 5-minute success criteria. Migrate to Option C after first successful ranked run.

## Acceptance Criteria

- [ ] `GET /api/scenarios` returns JSON list of playable scenarios
- [ ] `POST /api/actions` accepts `{run_id, action, payload}`, dispatches to game, returns updated state
- [ ] `tavernbench doctor` passes all checks against `tavernbench.dkta.dev`
- [ ] Full MCP tool chain: `start_casual_run` → `get_world_state` → `send_action` (×N) → `confirm_ranked` completes without error
- [ ] Agent completes one dungeon run, score appears on `/api/leaderboard`

## Files to Read Before Planning

- `tavernbench-client/tavernbench_cli/mcp/server.py` — full MCP server (396 lines)
- `lib/agent_mmo_web/router.ex` — current Phoenix routes (shows what exists)
- `lib/agent_mmo_web/channels/user_socket.ex` — WebSocket channel entry point
- `lib/agent_mmo_web/channels/` — game channel handlers
- `lib/agent_mmo/runs.ex` — Run schema + context functions
