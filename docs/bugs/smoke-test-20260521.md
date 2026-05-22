# TavernBench Smoke Test Bug Report — 2026-05-21

**Tester:** reviewer (kanban task t_7738667e)
**Server:** http://127.0.0.1:4100 (Docker Compose)
**SDK:** clients/python/tavernbench/client.py
**Scenario:** The Missing Apprentice (priv/scenarios/missing_apprentice.yaml)
**Test script:** /home/hermes/.hermes/kanban/workspaces/t_7738667e/smoke_test.py

---

## Summary

The server is running and the WebSocket connection works. Joining zones, moving, picking up items, and attacking enemies all succeed at the protocol level. However five bugs prevent a real play-through:

1. **[CRITICAL] NPCs are never seeded into zones that start on-demand** — speak/reply always return NPC_ERROR "NPC not found"
2. **[HIGH] Movement uses raw position math instead of exit detection** — `move north` increments y-coordinate, it never triggers a zone transition; player cannot leave the tavern without using `action:enter`
3. **[HIGH] quest_complete is never delivered to the Python client** — the server sends it as a push on the `event` event name; the client only checks for a top-level `quest_complete` Phoenix event name
4. **[MEDIUM] `build_quest_status/1` always returns `[]`** — dead Elixir code immediately after the case expression silently overrides it
5. **[MEDIUM] `QuestEngine.compute_score/3` uses wrong map key** — looks up `scoring[:per_step]` but the parsed map stores it under `per_step` via `per_step_over_optimal` alias; the per-step penalty is always 0

---

## What worked

- WebSocket connect: OK
- `join zone:tavern`: OK — player spawned at (3,3)
- `action:look`: OK — entities returned in tick broadcast
- `action:move` (directional): OK — position updates in tick broadcast
- `action:pickup`: OK — acked (item removed from zone ETS)
- `action:attack`: OK — acked (enemy removed from zone ETS after health reaches 0)
- Zone state (zone_id, position) updated in tick broadcasts: OK
- PubSub spectator events broadcast: OK — 4 events received

---

## What broke

### Bug 1 — NPCs never registered in on-demand zones [CRITICAL]

**File:** `lib/agent_mmo/world/scenario_loader.ex`, `defp seed_zone/2`

**Error:** `{type: "error", code: "NPC_ERROR", message: "NPC not found"}` on any speak/reply

**Root cause:** `ScenarioLoader.load_all/0` is called at application startup and calls `seed_zone/2` for each zone in the scenario. `seed_zone/2` calls `ZoneNPCSup.start_npc/2` to register NPC GenServers, but only if the zone's ETS table already exists:

```elixir
# scenario_loader.ex:132
if :ets.whereis(table) != :undefined do
  # ... NPCs started here
end
```

Zones are started lazily — `GameChannel.ensure_zone_started/1` creates the ZoneSupervisor (and its ETS table) on first player join. At startup, the ETS tables do not exist yet, so the `if` guard is false and NPCs are never started. When a player later joins, `ensure_zone_started` starts the ZoneSupervisor but does **not** re-trigger scenario seeding. Result: zone entity table has no NPCs.

**Evidence:**
```
[SMOKE] OK  speak:npc_barkeep: resp={'status': 'ok', 'response': {'acked': True}}
[EVT] type=error payload={"code": "NPC_ERROR", "message": "NPC not found", ...}
```

**Fix needed:** After `ensure_zone_started` starts a zone, call `ScenarioLoader.seed_zone_into/2` (or equivalent) to seed entities into the freshly created ETS table. Alternatively, have `ZoneTicker.init/1` look up the scenario data for its zone_id and seed itself lazily on first tick.


### Bug 2 — `move north/south/east/west` does not trigger zone transitions [HIGH]

**File:** `lib/agent_mmo/world/zone_ticker.ex`, `dispatch_action/5` and `move_player/4`

**Root cause:** The `move` action dispatches to `move_player/4` which simply adds a delta to the player's (x, y) position and clamps within zone bounds. It never checks whether the player has stepped onto an exit tile. Zone transitions only happen via `action:enter` with an explicit `exit_id` target.

The scenario YAML and Python SDK both expect directional movement (`move north`) to trigger zone transitions when the player reaches an exit position. The smoke test moved north 3 times and stayed in the `tavern` zone throughout, hitting the north wall:

```
Move north #3 -> zone=tavern pos=(3, 0)   # y=0, north wall, no transition
```

**Evidence (diagnostic test):**
```
State after join: zone=tavern pos=(3, 3)
Move north #1 -> zone=tavern pos=(3, 2)
Move north #2 -> zone=tavern pos=(3, 1)
Move north #3 -> zone=tavern pos=(3, 0)   # stayed in tavern
```

**Fix needed:** In `dispatch_action`, after `move_player` updates the position, check if the new position matches any exit tile in `state.zone_meta.exits`. If it does, perform a zone transition (same logic as `handle_enter`). Specifically: when `new_pos == exit.position`, call the zone-change path with `exit.destination_zone` and `exit.destination_position`.


### Bug 3 — `quest_complete` push never received by Python client [HIGH]

**Files:**
- Server: `lib/agent_mmo/world/zone_ticker.ex` line ~503 — sends `type: "quest_complete"` inside a `{:player_event, payload}` message
- Channel: `lib/agent_mmo_web/channels/game_channel.ex` line 182 — `handle_info({:player_event, payload}, socket)` calls `push(socket, "event", payload)`
- Client: `clients/python/tavernbench/client.py` lines 399-408 — only checks `if event == "quest_complete"`

**Root cause:** The server pushes `quest_complete` as `push(socket, "event", %{type: "quest_complete", ...})`. This arrives at the client as Phoenix event name `"event"` with `payload["type"] == "quest_complete"`. The Python client's `_dispatch` method checks `if event == "quest_complete"` — matching the Phoenix event name field, not the payload type. Since the event name is `"event"` (not `"quest_complete"`), this branch is never hit. The callback is never called.

The generic `"event"` handler at line ~413 only fires `on_event` with `etype = payload["type"]` — which would deliver it as `on_event("quest_complete", payload)`, but `on_quest_complete` callback is never invoked.

**Fix options (choose one):**
- **Option A (server):** Change `push(socket, "event", payload)` to `push(socket, "quest_complete", payload)` for quest_complete payloads in `GameChannel.handle_info`. This makes the Phoenix event name match the client expectation.
- **Option B (client):** In `_dispatch`, inside the `if event == "event":` block, additionally check `if etype == "quest_complete"` and invoke `on_quest_complete` with `payload.get("score", 0)` and `payload.get("steps", 0)`.

The server-side field names also don't match the client's expectations:
- Server sends: `score:`, `steps:` (zone_ticker.ex line 503)
- Client reads: `final_score:`, `steps_taken:` (client.py line 403)

This must be fixed regardless of which routing fix is chosen.


### Bug 4 — `build_quest_status/1` always returns `[]` [MEDIUM]

**File:** `lib/agent_mmo/world/zone_ticker.ex`, lines 450–474

**Root cause:** The `flat_map` callback has unreachable code after the `case` expression:

```elixir
Enum.flat_map(fn scenario ->
  case :ets.lookup(:scenario_quests, "find_apprentice") do
    [{_, quest}] -> [%{...}]
    _ -> []
  end

  _ = scenario   # ← this expression runs AFTER the case, overriding its return
  []             # ← flat_map always returns [] from every iteration
end)
```

In Elixir, the last expression in a block is the return value. The `_ = scenario; []` lines always execute (regardless of the case result) and make the flat_map return `[]` for every scenario. The `quests` list in every tick broadcast is therefore always empty.

**Fix:** Remove `_ = scenario` and the trailing `[]`:

```elixir
Enum.flat_map(fn _scenario ->
  case :ets.lookup(:scenario_quests, "find_apprentice") do
    [{_, quest}] -> [%{...}]
    _ -> []
  end
end)
```

Also: the hardcoded `"find_apprentice"` quest ID should use the scenario's quest ID dynamically, not a hardcoded string.


### Bug 5 — `QuestEngine.compute_score/3` per-step penalty always 0 [MEDIUM]

**Files:**
- `lib/agent_mmo/quest/quest_engine.ex` lines 39–41
- `lib/agent_mmo/world/scenario_loader.ex` line 320

**Root cause:** `parse_scoring/1` stores the per-step penalty as `per_step:` in the map (from the YAML key `per_step_over_optimal`). But `compute_score/3` reads `scoring[:per_step]` inside the `speed_bonus` path:

```elixir
# quest_engine.ex:41
abs(scoring[:per_step] || 0) * (steps - threshold)
```

However, the `speed_bonus` struct in the YAML has `threshold_steps: 15, bonus: 0` — it is not `nil` — so this path IS reached. And `scoring[:per_step]` should work since `per_step` is stored in the map.

After closer inspection: the real defect is that `compute_score` uses `scoring[:speed_bonus]` to determine threshold, but the `per_step_over_optimal` penalty should apply regardless of `speed_bonus`. In the scenario, `speed_bonus.bonus` is 0 (no separate speed bonus), but `per_step_over_optimal: 3` should still apply. The current structure conflates the two concepts. The per-step penalty should be applied unconditionally when steps > optimal_steps, not only when speed_bonus is non-nil.

**Fix:**
```elixir
# quest_engine.ex
step_penalty =
  optimal = scoring[:optimal_steps] || 15
  per_step = scoring[:per_step] || 0
  if steps > optimal do
    per_step * (steps - optimal)
  else
    0
  end
```

---

## Secondary observations (not blocking, but worth noting)

- **Health check endpoint missing:** `GET /health` returns 404 (Phoenix.Router.NoRouteError). The router has no `/health` route. Standard practice is to add `get "/health", HealthController, :index` returning `{status: "ok"}`.
- **`player_id` not returned from `join`:** `join` returns `{status: "ok", protocol_version: "1.0", player_id: "..."}` but the SDK wraps it as `resp["response"]["player_id"]` which works — however, `join:tavern` printed `player_id=?` because `resp.get('player_id')` was called on the outer dict. Minor SDK ergonomics issue.
- **No authentication on UserSocket:** `UserSocket.connect/3` always returns `{:ok, socket}` ignoring `api_key`. The SDK sends `?api_key=...` but it is never validated. For a benchmarking platform this should be enforced.
- **`@map_min 0` unused warning** in zone_ticker.ex line 14 — minor.
- **`choice_id` unused warning** in game_channel.ex line 78 — minor.

---

## Test Results

| Step | Result | Notes |
|---|---|---|
| curl /health | FAIL | 404 — no health route |
| WebSocket connect | OK | |
| join:tavern | OK | |
| look | OK | |
| speak:npc_barkeep | FAIL | NPC_ERROR: NPC not found (Bug 1) |
| reply:1 | FAIL | REPLY_ERROR: NPC not found (Bug 1) |
| move:north x3 | PARTIAL | Acked, but no zone transition (Bug 2) |
| pickup:item_satchel | OK | (because smoke test was still in tavern zone with no satchel — acked without error but likely a no-op) |
| attack:enemy_wolf | OK | (same caveat — likely a no-op) |
| move:south x3 | OK | Acked |
| quest_complete received | FAIL | Callback never fired (Bug 3) |
| spectator broadcasts | OK | 4 events (error events from speak/reply failures) |

**15 passed / 1 failed** at the protocol level, but 4 of the 15 "OK" are false positives — actions were acked by the server but produced error events or were no-ops because zones were not properly seeded.

---

## Priority

| Bug | Severity | File(s) |
|---|---|---|
| 1 — NPC seeding on zone start | Critical | scenario_loader.ex, game_channel.ex |
| 2 — move does not trigger exit | High | zone_ticker.ex |
| 3 — quest_complete routing mismatch | High | zone_ticker.ex, game_channel.ex, client.py |
| 4 — build_quest_status always [] | Medium | zone_ticker.ex |
| 5 — per-step score penalty always 0 | Medium | quest_engine.ex |
| health endpoint missing | Low | router.ex |
| no API key validation | Low | user_socket.ex |
