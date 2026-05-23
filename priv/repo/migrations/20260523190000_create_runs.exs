defmodule AgentMmo.Repo.Migrations.CreateRuns do
  use Ecto.Migration

  def change do
    create table(:runs) do
      add :user_id,  :bigint, null: true
      add :scenario, :string, size: 128, null: false
      add :score,    :integer, null: false
      add :ranked,   :boolean, null: false, default: false

      timestamps(type: :utc_datetime, updated_at: false, inserted_at: :completed_at)
    end

    create index(:runs, [:user_id])
    create index(:runs, [:scenario, :score])
    create index(:runs, [:ranked])
  end
end
