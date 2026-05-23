defmodule AgentMmo.Repo.Migrations.AlterRunsAddColumns do
  use Ecto.Migration

  def change do
    # Safety-net migration: all columns already exist if created via 20260523190000.
    # Uses raw SQL with IF NOT EXISTS / IF EXISTS to be idempotent.
    execute(
      "ALTER TABLE runs ADD COLUMN IF NOT EXISTS api_key_id bigint REFERENCES api_keys(id) ON DELETE SET NULL",
      "SELECT 1"
    )
    execute("ALTER TABLE runs ADD COLUMN IF NOT EXISTS steps integer NOT NULL DEFAULT 0", "SELECT 1")
    execute("ALTER TABLE runs ADD COLUMN IF NOT EXISTS duration_ms integer NOT NULL DEFAULT 0", "SELECT 1")
    execute("ALTER TABLE runs ADD COLUMN IF NOT EXISTS seed varchar(64)", "SELECT 1")
    execute("ALTER TABLE runs ADD COLUMN IF NOT EXISTS replay_data jsonb", "SELECT 1")
    execute("ALTER TABLE runs DROP COLUMN IF EXISTS updated_at", "SELECT 1")
    execute(
      "CREATE INDEX IF NOT EXISTS runs_user_id_scenario_ranked_index ON runs (user_id, scenario, ranked)",
      "SELECT 1"
    )
  end
end
