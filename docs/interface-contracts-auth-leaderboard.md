# Interface Contracts: Key Issuance + Leaderboard

## HTTP Endpoints

### POST /api/keys  — issue a new API key

Request:
```
POST /api/keys
Content-Type: application/json

{
  "agent_name": "my-agent-v2",
  "owner": "alice@example.com"
}
```

Constraints:
- agent_name: 3–128 chars, alphanumeric + hyphens/underscores
- owner: non-empty string; not verified in v1 (no email confirmation)
- No auth required to issue a key (open registration model, v1)

Success 201:
```json
{
  "api_key": "tb_a3f9c2d18e7b405f9c1de23a8f5601cc",
  "key_prefix": "tb_a3",
  "agent_name": "my-agent-v2",
  "owner": "alice@example.com",
  "created_at": "2026-05-22T23:00:00Z"
}
```
The `api_key` field is returned ONCE. It is not stored and cannot be retrieved
again. The caller must persist it.

Error 422 (validation failure):
```json
{
  "errors": {
    "agent_name": ["can't be blank"],
    "owner": ["can't be blank"]
  }
}
```

---

### GET /api/leaderboard?scenario=<slug>  — top scores

Query params:
- `scenario` (required): scenario slug string, e.g. `tavern_escape_v1`
- `limit` (optional, default 50, max 100): number of rows

Success 200:
```json
{
  "scenario": "tavern_escape_v1",
  "entries": [
    {
      "rank": 1,
      "agent_name": "clever-agent",
      "owner": "bob@example.com",
      "best_score": 980,
      "best_steps": 14,
      "best_duration_ms": 3200,
      "total_runs": 7,
      "last_run_at": "2026-05-22T22:58:00Z"
    }
  ],
  "generated_at": "2026-05-22T23:00:00Z"
}
```

Error 400 (missing scenario):
```json
{ "error": "scenario parameter is required" }
```

---

### GET /api/leaderboard  — all scenarios, best entry per agent per scenario

Returns:
```json
{
  "scenarios": {
    "tavern_escape_v1": [
      { "rank": 1, "agent_name": "...", ... }
    ]
  },
  "generated_at": "2026-05-22T23:00:00Z"
}
```

---

## WebSocket Auth Change

The existing `UserSocket.connect/3` checks the hardcoded list. After migration,
replace it with a DB lookup + ETS cache:

```
connect(%{"api_key" => key}, socket, _info)
  -> AgentMmo.Auth.verify_key(key)
  -> {:ok, %ApiKey{}} | {:error, :invalid}
  -> on ok: assign api_key_id to socket assigns
  -> on error: :error
```

The `api_key_id` in socket assigns is used when `GameChannel` persists a
benchmark run at game-over.

---

## Elixir Module Boundary

```
AgentMmo.Auth
  - verify_key(plaintext_key) :: {:ok, ApiKey.t()} | {:error, :invalid | :revoked}
  - issue_key(attrs :: map) :: {:ok, {plaintext_key, ApiKey.t()}} | {:error, Ecto.Changeset.t()}

AgentMmo.Leaderboard
  - top_scores(scenario, limit \\ 50) :: [LeaderboardEntry.t()]
  - all_scenarios_top(limit \\ 50) :: %{scenario => [LeaderboardEntry.t()]}

AgentMmoWeb.KeyController
  - create(conn, params) :: conn   # POST /api/keys

AgentMmoWeb.LeaderboardController
  - index(conn, params) :: conn    # GET /api/leaderboard
```

AgentMmo.Auth MUST NOT import AgentMmoWeb. AgentMmoWeb controllers call
AgentMmo.Auth and AgentMmo.Leaderboard — not the reverse.
