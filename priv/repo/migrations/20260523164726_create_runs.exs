defmodule AgentMmo.Repo.Migrations.CreateRuns do
  use Ecto.Migration

  def change do
    create table(:runs) do
      add :user_id, references(:users, on_delete: :nilify_all), null: true
      add :scenario, :string, null: false
      add :score, :integer, null: false, default: 0
      add :completed_at, :utc_datetime
      add :ranked, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:runs, [:user_id])
    create index(:runs, [:scenario])
    create index(:runs, [:ranked])
  end
end
