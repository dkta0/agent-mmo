# Schema Design: API Keys + Benchmark Runs

## Tables

### api_keys

```sql
CREATE TABLE api_keys (
  id         bigserial PRIMARY KEY,
  key_hash   char(64)     NOT NULL UNIQUE,   -- SHA-256 hex of plaintext key
  key_prefix char(5)      NOT NULL,           -- first 5 chars of plaintext (tb_xx), for display
  agent_name varchar(128) NOT NULL,
  owner      varchar(256) NOT NULL,           -- email or handle; not verified in v1
  created_at timestamptz  NOT NULL DEFAULT now(),
  revoked_at timestamptz                      -- NULL = active
);

CREATE INDEX api_keys_hash_idx ON api_keys (key_hash)
  WHERE revoked_at IS NULL;
```

### benchmark_runs

```sql
CREATE TABLE benchmark_runs (
  id           bigserial    PRIMARY KEY,
  api_key_id   bigint       NOT NULL REFERENCES api_keys(id),
  scenario     varchar(128) NOT NULL,          -- scenario slug, e.g. "tavern_escape_v1"
  score        integer      NOT NULL,
  steps        integer      NOT NULL,
  duration_ms  integer      NOT NULL,          -- wall-clock ms for the run
  completed_at timestamptz  NOT NULL DEFAULT now()
);

-- Leaderboard query support: best score per (agent, scenario)
CREATE INDEX runs_key_scenario_idx ON benchmark_runs (api_key_id, scenario, score DESC);

-- Top-N across all agents for a given scenario
CREATE INDEX runs_scenario_score_idx ON benchmark_runs (scenario, score DESC, completed_at DESC);
```

## Ecto Migration Stubs (for coder)

Two migrations, in order:

### 1. create_api_keys

```elixir
defmodule AgentMmo.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys) do
      add :key_hash,   :string,  size: 64,  null: false
      add :key_prefix, :string,  size: 5,   null: false
      add :agent_name, :string,  size: 128, null: false
      add :owner,      :string,  size: 256, null: false
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:api_keys, [:key_hash])
    create index(:api_keys, [:key_hash], where: "revoked_at IS NULL", name: :api_keys_active_hash_idx)
  end
end
```

### 2. create_benchmark_runs

```elixir
defmodule AgentMmo.Repo.Migrations.CreateBenchmarkRuns do
  use Ecto.Migration

  def change do
    create table(:benchmark_runs) do
      add :api_key_id,  references(:api_keys, on_delete: :restrict), null: false
      add :scenario,    :string,  size: 128, null: false
      add :score,       :integer, null: false
      add :steps,       :integer, null: false
      add :duration_ms, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false, inserted_at: :completed_at)
    end

    create index(:benchmark_runs, [:api_key_id, :scenario])
    create index(:benchmark_runs, [:scenario, :score])
  end
end
```

## Leaderboard Query Shape

Best score per agent per scenario (for the leaderboard):

```sql
SELECT
  ak.agent_name,
  ak.owner,
  br.scenario,
  MAX(br.score)        AS best_score,
  MIN(br.steps)        AS best_steps,
  MIN(br.duration_ms)  AS best_duration_ms,
  COUNT(*)             AS total_runs,
  MAX(br.completed_at) AS last_run_at
FROM benchmark_runs br
JOIN api_keys ak ON ak.id = br.api_key_id
WHERE ak.revoked_at IS NULL
  AND br.scenario = $1           -- parameterise per scenario
GROUP BY ak.agent_name, ak.owner, br.scenario
ORDER BY best_score DESC, best_steps ASC, best_duration_ms ASC
LIMIT 50;
```

Ties broken by steps then duration. This is safe to add as a named Ecto query
in `AgentMmo.Leaderboard` context module.
