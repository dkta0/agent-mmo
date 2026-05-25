defmodule AgentMmo.Repo.Migrations.CreateRunTranscripts do
  use Ecto.Migration

  def change do
    create table(:run_transcripts) do
      add :benchmark_run_id, references(:benchmark_runs, on_delete: :delete_all), null: false
      add :tick_no,    :integer, null: false
      add :action,     :map,     null: false
      add :tick,       :map,     null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:run_transcripts, [:benchmark_run_id, :tick_no])
  end
end
