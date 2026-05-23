defmodule AgentMmo.Repo.Migrations.CreateTickLogs do
  use Ecto.Migration

  def change do
    create table(:tick_logs) do
      add :run_id,      references(:runs, on_delete: :delete_all), null: false
      add :tick,        :integer, null: false
      add :action,      :string,  size: 64, null: false
      add :action_args, :map
      add :result,      :string,  size: 64, null: false, default: "ok"
      add :score_delta, :integer, null: false, default: 0
      add :hp_after,    :integer
      add :x,           :integer
      add :y,           :integer

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:tick_logs, [:run_id, :tick])
  end
end
