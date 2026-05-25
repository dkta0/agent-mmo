defmodule AgentMmo.RunTranscript do
  use Ecto.Schema
  import Ecto.Changeset

  schema "run_transcripts" do
    field :tick_no, :integer
    field :action,  :map
    field :tick,    :map

    belongs_to :benchmark_run, AgentMmo.BenchmarkRun

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(rt, attrs) do
    rt
    |> cast(attrs, [:benchmark_run_id, :tick_no, :action, :tick])
    |> validate_required([:benchmark_run_id, :tick_no, :action, :tick])
    |> unique_constraint([:benchmark_run_id, :tick_no])
  end
end
