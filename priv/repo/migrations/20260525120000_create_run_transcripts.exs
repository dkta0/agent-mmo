defmodule AgentMmo.Repo.Migrations.CreateRunTranscripts do
  use Ecto.Migration

  def change do
    create table(:run_transcripts) do
      add :benchmark_run_id, references(:benchmark_runs, on_delete: :delete_all), null: false
      add :tick_no,    :integer, null: false
      add :action,     :map,     null: false
      add :tick,       :map,     null: false
      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:run_transcripts, [:benchmark_run_id, :tick_no])
  end
end
