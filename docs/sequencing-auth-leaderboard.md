# Implementation Sequencing: Auth + Leaderboard

## Why This Order

Each step produces a running, testable slice. No step requires the next to be
done first.

---

## Step 1 — Migrations (no code changes, zero risk)

1. Generate and run migration: `create_api_keys`
2. Generate and run migration: `create_benchmark_runs`
3. Verify both tables exist in dev Postgres.
4. Do NOT touch config or runtime code yet.

Commands:
```
sudo docker compose exec app mix ecto.gen.migration create_api_keys
sudo docker compose exec app mix ecto.gen.migration create_benchmark_runs
# fill in change/0 per schema-api-keys-leaderboard.md
sudo docker compose exec app mix ecto.migrate
```

---

## Step 2 — Ecto schemas + AgentMmo.Auth context

1. Create `AgentMmo.ApiKey` schema (maps to api_keys table).
2. Create `AgentMmo.BenchmarkRun` schema (maps to benchmark_runs table).
3. Implement `AgentMmo.Auth`:
   - `issue_key/1`: generate `tb_<32 hex>`, SHA-256 hash, insert row, return
     `{plaintext, %ApiKey{}}`.
   - `verify_key/1`: hash incoming key, query active row, cache result in ETS
     table `:api_key_cache` with 60s TTL.
4. Unit-test Auth in isolation (DataCase).

ETS table setup: start it in `AgentMmo.Application` before the Repo.
Key for cache: plaintext key string. Value: `{:ok, api_key_id}` or `:invalid`.
TTL eviction: use `:ets.select_delete` on a scheduled task or accept stale for
the 60s window (acceptable; revoked keys are rare).

---

## Step 3 — Replace hardcoded auth in UserSocket

1. Change `UserSocket.connect/3` to call `AgentMmo.Auth.verify_key/1`.
2. On `{:ok, %ApiKey{id: id}}`, do `assign(socket, :api_key_id, id)`.
3. Remove `valid_api_keys` from config.exs.
4. Add `"dev-key"` as a seed row in `priv/repo/seeds.exs` so dev still works.
5. Smoke-test: connect with `dev-key` via the existing client.

This is the only step that touches live request handling. Do it as an atomic
PR so it's easy to revert.

---

## Step 4 — AgentMmo.Leaderboard + GET /api/leaderboard

1. Implement `AgentMmo.Leaderboard.top_scores/2` using the named query from the
   schema doc.
2. Create `AgentMmoWeb.LeaderboardController` with `index/2`.
3. Add route: `get "/leaderboard", LeaderboardController, :index` under
   `/api` scope.
4. Test: insert a few benchmark_runs rows in DataCase, assert ordering.

No auth required on GET /api/leaderboard (public read).

---

## Step 5 — POST /api/keys (key issuance endpoint)

1. Create `AgentMmoWeb.KeyController` with `create/2`.
2. Add route: `post "/keys", KeyController, :create` under `/api` scope.
3. Validate params, call `AgentMmo.Auth.issue_key/1`, return 201 with plaintext
   key in body.
4. Test: assert 201 response shape, assert DB row created, assert plaintext not
   in DB.

---

## Step 6 — Wire GameChannel to persist benchmark runs

1. At game-over in `GameChannel`, read `socket.assigns.api_key_id`.
2. Insert a `BenchmarkRun` row (scenario, score, steps, duration_ms).
3. Broadcast the updated leaderboard via PubSub so any connected spectators or
   the web UI refresh automatically.

This step depends on Step 3 (api_key_id in assigns) and Step 2 (BenchmarkRun
schema). Steps 4 and 5 can be done in parallel with Step 6.

---

## Dependency Graph

```
Step 1 (migrations)
  └─> Step 2 (schemas + Auth)
        └─> Step 3 (UserSocket)
              └─> Step 6 (GameChannel persist)
        └─> Step 4 (Leaderboard endpoint)   [independent of Step 3]
        └─> Step 5 (Key issuance endpoint)  [independent of Step 3]
```

Steps 4, 5, 6 can be parallelised after Step 2 lands.
