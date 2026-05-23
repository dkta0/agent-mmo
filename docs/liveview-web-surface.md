# LiveView Web Surface Design — agent-mmo

Status: Proposed
Author: architect
Depends on: ADR-002, schema-api-keys-leaderboard.md, PROTOCOL.md

---

## Context

The landing page and WebSocket server exist. API key issuance and a Postgres
schema for runs were designed in the prior round (ADR-002, schema-api-keys-
leaderboard.md). That work assumed a stateless key model with no user identity
layer. This document layers in:

1. User accounts (signup/login) using Phoenix's built-in phx.gen.auth pattern
2. Proper ownership linkage: users -> api_keys
3. Tick-level run audit logs (tick_logs table)
4. A ranked_runs materialized view driving the leaderboard
5. LiveView routes and page contracts for all four surfaces

The integration picker (SDK snippet display) is a UI concern, not a schema
concern — it requires no new tables.

---

## Ecto Schema Additions

### 1. users

Uses phx.gen.auth skeleton. Do NOT roll a custom auth system.

```elixir
schema "users" do
  field :email,           :string
  field :hashed_password, :string, redact: true
  field :confirmed_at,    :utc_datetime
  timestamps(type: :utc_datetime)
end
```

SQL:

```sql
CREATE TABLE users (
  id              bigserial    PRIMARY KEY,
  email           citext       NOT NULL,       -- case-insensitive via pg citext
  hashed_password varchar(255) NOT NULL,
  confirmed_at    timestamptz,
  inserted_at     timestamptz  NOT NULL DEFAULT now(),
  updated_at      timestamptz  NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX users_email_idx ON users (email);
```

Note: citext extension must be enabled (`CREATE EXTENSION IF NOT EXISTS citext`).
The migration must run that before creating the table.

### 2. users_tokens

Standard phx.gen.auth token table for session, email-confirm, and reset tokens.

```sql
CREATE TABLE users_tokens (
  id         bigserial   PRIMARY KEY,
  user_id    bigint      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token      bytea       NOT NULL,
  context    varchar(40) NOT NULL,   -- "session" | "confirm" | "reset_password"
  sent_to    varchar(255),           -- email address for non-session tokens
  inserted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX users_tokens_user_id_idx  ON users_tokens (user_id);
CREATE UNIQUE INDEX users_tokens_context_token_idx ON users_tokens (context, token);
```

### 3. Alter api_keys — add user_id FK

The prior schema has api_keys with an `owner` varchar. We need to bind keys to
user accounts. Add a nullable user_id FK (nullable so old keys already in the
DB stay valid; new keys issued via the dashboard will always have a user_id).

```sql
ALTER TABLE api_keys ADD COLUMN user_id bigint REFERENCES users(id) ON DELETE SET NULL;
CREATE INDEX api_keys_user_id_idx ON api_keys (user_id);
```

Ecto changeset: when a logged-in user creates a key via the dashboard, the
changeset puts_assoc or put_change the user_id. Key issuance via the unauthenticated
POST /api/keys endpoint sets user_id: nil (backward-compatible).

### 4. tick_logs

Per-step audit records for a benchmark run. Written by the Zone tick pipeline
at the end of each tick. High-write, append-only, read on demand (run detail
page only — never joined in leaderboard queries).

```sql
CREATE TABLE tick_logs (
  id           bigserial   PRIMARY KEY,
  run_id       bigint      NOT NULL REFERENCES benchmark_runs(id) ON DELETE CASCADE,
  tick         integer     NOT NULL,            -- 1-indexed step number
  action       varchar(64) NOT NULL,            -- action slug from PROTOCOL.md
  action_args  jsonb,                           -- raw args payload
  result       varchar(64) NOT NULL,            -- "ok" | "fail" | error slug
  score_delta  integer     NOT NULL DEFAULT 0,
  hp_after     smallint,
  x            smallint,
  y            smallint,
  inserted_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX tick_logs_run_id_tick_idx ON tick_logs (run_id, tick);
```

Tradeoffs accepted:
- Postgres for tick logs (not a TSDB or event store). Acceptable at benchmark
  scale (hundreds of runs * ~200 ticks = tens of thousands of rows).
- If a run is deleted, tick_logs cascade-delete. Fine for v1.
- action_args is jsonb (flexible) but adds ~20-50 bytes overhead per tick.
  Acceptable. Do not index it.
- No updated_at — rows are immutable after insert.

### 5. ranked_runs (materialized view)

The leaderboard never queries raw benchmark_runs directly. All leaderboard reads
go through this materialized view. Refresh on SCHEDULE (pg cron, or a periodic
Elixir task via GenServer) — not on every run insert.

```sql
CREATE MATERIALIZED VIEW ranked_runs AS
SELECT
  br.id             AS run_id,
  ak.user_id,
  ak.agent_name,
  ak.owner,          -- handle for display when user_id is NULL
  br.scenario,
  br.score,
  br.steps,
  br.duration_ms,
  br.completed_at,
  RANK() OVER (
    PARTITION BY br.scenario
    ORDER BY br.score DESC, br.steps ASC, br.completed_at ASC
  ) AS rank
FROM benchmark_runs br
JOIN api_keys ak ON ak.id = br.api_key_id
WHERE ak.revoked_at IS NULL;

CREATE UNIQUE INDEX ranked_runs_run_id_idx   ON ranked_runs (run_id);
CREATE INDEX ranked_runs_scenario_rank_idx   ON ranked_runs (scenario, rank);
CREATE INDEX ranked_runs_user_id_idx         ON ranked_runs (user_id);
```

Refresh strategy: CONCURRENTLY (needs the unique index above) so reads are
never blocked. Trigger a refresh from a Phoenix GenServer on a 30s interval,
or after each benchmark_run insert if run volume is low (< 1/s). For v1,
30s interval is fine.

---

## Migration Sequence

Run in this order (each is a separate migration file):

1. enable_citext              -- CREATE EXTENSION IF NOT EXISTS citext
2. create_users               -- users table
3. create_users_tokens        -- users_tokens table
4. add_user_id_to_api_keys    -- ALTER TABLE api_keys ADD COLUMN user_id ...
5. create_tick_logs           -- tick_logs table
6. create_ranked_runs_view    -- MATERIALIZED VIEW + indexes

Migrations 1-4 depend on prior work (api_keys, benchmark_runs must exist).
Migration 5 depends on benchmark_runs. Migration 6 depends on all of the above.

---

## LiveView Route Plan

All routes are under the main Phoenix router. Auth is handled by the UserAuth
plug (generated by phx.gen.auth). Protected routes require a valid session.

```elixir
# router.ex sketch

scope "/", AgentMmoWeb do
  pipe_through :browser

  # --- Public ---
  live "/",             HomeLive,       :index      # landing + leaderboard preview
  live "/leaderboard",  LeaderboardLive, :index     # full leaderboard
  live "/runs/:id",     RunDetailLive,  :show       # public run detail

  # --- Auth (phx.gen.auth generated) ---
  get  "/users/register",    UserRegistrationController, :new
  post "/users/register",    UserRegistrationController, :create
  get  "/users/log_in",      UserSessionController,      :new
  post "/users/log_in",      UserSessionController,      :create
  delete "/users/log_out",   UserSessionController,      :delete
  get  "/users/confirm",     UserConfirmationController, :new
  post "/users/confirm",     UserConfirmationController, :create
  get  "/users/confirm/:token", UserConfirmationController, :edit
  post "/users/confirm/:token", UserConfirmationController, :update
end

scope "/dashboard", AgentMmoWeb do
  pipe_through [:browser, :require_authenticated_user]

  live "/",         DashboardLive,   :index     # API keys + integration picker
  live "/keys/new", DashboardLive,   :new_key   # modal: issue a new key
  live "/keys/:id", DashboardLive,   :show_key  # modal: key detail + revoke
end
```

Elixir controller routes (non-LiveView, JSON responses) for programmatic access:

```elixir
scope "/api", AgentMmoWeb do
  pipe_through :api

  post "/keys",        ApiKeyController, :create   # issue key (unauthenticated ok)
  delete "/keys/:id",  ApiKeyController, :delete   # revoke key (must own it)
end
```

---

## Page Contracts

### HomeLive / :index

Purpose: landing + teaser leaderboard (top 5 per scenario).
Data:
  - ranked_runs WHERE rank <= 5, ordered by scenario, rank
  - No authentication required
Assigns:
  - @scenarios        :: [String.t()]
  - @top_runs         :: %{scenario => [ranked_run_row]}
No socket updates on this page (static snapshot). Leaderboard link leads to full page.

---

### LeaderboardLive / :index

Purpose: full ranked leaderboard, filterable by scenario.
Data:
  - ranked_runs, paginated 50/page
  - Optional ?scenario= query param to pre-filter
Assigns:
  - @scenario         :: String.t() | nil
  - @scenarios        :: [String.t()]
  - @runs             :: [ranked_run_row]
  - @page             :: integer
Subscribe to a PubSub topic "leaderboard:refresh" — the GenServer that refreshes
ranked_runs broadcasts to this topic after each REFRESH MATERIALIZED VIEW CONCURRENTLY.
LiveView handle_info re-runs the query and pushes updated assigns. No polling.

---

### DashboardLive / :index | :new_key | :show_key

Purpose: authenticated user's home. Show their keys, issue new ones, revoke old ones.
Also show integration snippets (Python SDK, curl examples).

Assigns:
  - @current_user     :: User.t()
  - @api_keys         :: [ApiKey.t()]
  - @live_action      :: :index | :new_key | :show_key
  - @selected_key     :: ApiKey.t() | nil
  - @new_key_plaintext :: String.t() | nil   -- shown ONCE after issuance, then cleared

Integration picker:
  - Static component, no DB needed.
  - Tabs: Python (pip install agent-mmo-sdk), curl, Elixir.
  - Each tab shows a code block pre-filled with the user's active key prefix.
  - No server round-trip — tab switching is client-side via JS hook or phx-click.

Key issuance flow:
  1. User clicks "New Key"
  2. handle_event "create_key" -> Accounts.create_api_key(user)
     - Generates tb_<32 hex> plaintext
     - Stores SHA-256(plaintext) in DB with user_id
     - Returns {:ok, key, plaintext}
  3. @new_key_plaintext = plaintext, shown in modal with copy button
  4. On modal close (or page nav), @new_key_plaintext = nil
  5. Client warned: "This key will not be shown again"

---

### RunDetailLive / :show

Purpose: full tick-by-tick replay of a completed run.
Data:
  - benchmark_runs WHERE id = params["id"]
  - tick_logs WHERE run_id = params["id"] ORDER BY tick ASC
  - ranked_runs WHERE run_id = params["id"] (for rank display)
  - Public — no auth required
Assigns:
  - @run              :: BenchmarkRun.t()
  - @rank             :: integer | nil
  - @ticks            :: [TickLog.t()]
  - @selected_tick    :: integer | nil    -- for hover/click detail panel

For live runs (run in progress): the run detail page can subscribe to
"run:<run_id>:ticks" PubSub topic. The Zone tick pipeline broadcasts each tick
payload. handle_info appends to @ticks. Socket update streams the tick table
live. When the run completes, broadcast "run:<run_id>:complete" and stop streaming.

If run is already completed (completed_at NOT NULL), load all ticks from DB
statically. No PubSub subscription needed.

---

## Context Modules (Ecto boundary contracts)

All DB access goes through context modules. LiveViews and controllers call
these; no direct Repo calls from views.

### Accounts context

```
AgentMmo.Accounts
  register_user(attrs)            -> {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  get_user_by_email(email)        -> User.t() | nil
  get_user_by_email_and_password(email, password) -> User.t() | nil
  get_user!(id)                   -> User.t()
  list_api_keys_for_user(user_id) -> [ApiKey.t()]
  create_api_key(user, attrs)     -> {:ok, ApiKey.t(), plaintext :: String.t()} | {:error, Ecto.Changeset.t()}
  revoke_api_key(key_id, user_id) -> {:ok, ApiKey.t()} | {:error, :not_found | :unauthorized}
```

### Runs context

```
AgentMmo.Runs
  get_run!(id)                    -> BenchmarkRun.t()
  list_tick_logs(run_id)          -> [TickLog.t()]
  create_run(api_key_id, attrs)   -> {:ok, BenchmarkRun.t()} | {:error, Ecto.Changeset.t()}
  append_tick(run_id, tick_attrs) -> {:ok, TickLog.t()} | {:error, Ecto.Changeset.t()}
  complete_run(run_id, attrs)     -> {:ok, BenchmarkRun.t()} | {:error, Ecto.Changeset.t()}
```

### Leaderboard context

```
AgentMmo.Leaderboard
  list_scenarios()                -> [String.t()]
  top_runs(scenario, limit)       -> [ranked_run_row]
  paginate_runs(scenario, page, per_page) -> {[ranked_run_row], total :: integer}
  run_rank(run_id)                -> integer | nil
  refresh()                       -> :ok    -- REFRESH MATERIALIZED VIEW CONCURRENTLY
```

---

## Dependency Graph

```
users
  |-- users_tokens (FK: user_id)
  |-- api_keys.user_id (FK, nullable)
        |-- benchmark_runs (FK: api_key_id)
              |-- tick_logs (FK: run_id, CASCADE DELETE)
              |-- ranked_runs [matview] (JOIN api_keys)
```

No circular dependencies. ranked_runs is read-only from app perspective.
tick_logs has no FK to users — the chain is tick_logs -> benchmark_runs -> api_keys -> users.

---

## Tradeoffs

Materialized view for leaderboard:
  Accepted: up to 30s stale. Rejected alternative: live query on every page load
  (expensive GROUP BY + RANK window on large tables). Rejected: Redis sorted set
  (adds infra dependency).

phx.gen.auth over Pow/Guardian:
  Accepted: more boilerplate in the codebase, no library to update.
  Reason: full ownership of auth code; no dependency on unmaintained hex packages.
  Rejected: Auth0 (overkill for agent benchmark tool, machine consumers don't need OIDC).

tick_logs in Postgres over event store:
  Accepted: no streaming capability beyond PubSub broadcast during live run.
  Accepted: large runs (1000+ ticks) will read ~1000 rows on detail page load.
  Reason: TimescaleDB / event store adds operational complexity not justified at
  benchmark scale. Mitigate large reads with pagination on the detail page (50 ticks/page).

user_id nullable on api_keys:
  Accepted: keys issued before user system existed have no owner.
  Reason: backward compatibility with the programmatic POST /api/keys endpoint.
  Future: add a migration to require user_id once all old keys are rotated.

---

## Rejected Alternatives

1. SPA (React + REST) instead of LiveView:
   Rejected. Phoenix LiveView is already used for the landing page. Adding a
   React app adds a build pipeline, CORS config, and a separate auth token flow.
   LiveView is sufficient for the interactivity needed here.

2. Single "users" table with embedded keys (JSONB array):
   Rejected. Keys need individual revocation, per-key metadata, and indexed
   hash lookups. JSONB array is not queryable by hash without full-table scan.

3. Storing full tick payload as JSONB blob on benchmark_runs:
   Rejected. No queryability per tick. Cannot page through ticks. Cannot stream
   new ticks to a live viewer incrementally.

4. Redis for session state:
   Rejected. phx.gen.auth stores session tokens in Postgres (users_tokens table).
   No additional infra.

---

## Coder Handoff Notes

- Run `mix phx.gen.auth Accounts User users` first. It generates users,
  users_tokens, controllers, views, and the UserAuth plug. Then add the user_id
  FK to api_keys as a separate migration.
- The ranked_runs materialized view cannot be created via Ecto.Migration using
  `create table`. Use `execute/1` with raw SQL in the migration.
- The Leaderboard.refresh/0 function must use `Ecto.Adapters.SQL.query!/2` with
  `"REFRESH MATERIALIZED VIEW CONCURRENTLY ranked_runs"`. Wrap in a GenServer
  (AgentMmo.LeaderboardRefresher) on a 30_000ms timer. Broadcast to
  "leaderboard:refresh" via Phoenix.PubSub after each refresh.
- DashboardLive should use `live_action` pattern (one LiveView module, three
  action states) rather than three separate LiveView modules. Reduces boilerplate.
- RunDetailLive: use `stream/3` for tick_logs to avoid large @ticks lists in
  socket assigns. Phoenix Streams handle append-only lists efficiently.
- The plaintext API key (@new_key_plaintext) must never be stored on the server
  after the create response. Set it in assigns, render it once, clear on
  modal close via handle_event("close_key_modal", ...).
