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
