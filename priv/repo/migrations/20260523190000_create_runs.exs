defmodule AgentMmo.Repo.Migrations.CreateRuns do
  use Ecto.Migration

  def change do
    create table(:runs) do
      add :user_id,     references(:users, on_delete: :nilify_all), null: true
      add :api_key_id,  references(:api_keys, on_delete: :nilify_all), null: true
      add :scenario,    :string,  size: 128, null: false
      add :score,       :integer, null: false, default: 0
      add :steps,       :integer, null: false, default: 0
      add :duration_ms, :integer, null: false, default: 0
      add :ranked,      :boolean, null: false, default: false
      add :seed,        :string,  size: 64
      add :replay_data, :map

      timestamps(type: :utc_datetime, updated_at: false, inserted_at: :completed_at)
    end

    create index(:runs, [:user_id])
    create index(:runs, [:api_key_id])
    create index(:runs, [:scenario, :score])
    create index(:runs, [:ranked])
    create index(:runs, [:user_id, :scenario, :ranked, :completed_at])
  end
end
