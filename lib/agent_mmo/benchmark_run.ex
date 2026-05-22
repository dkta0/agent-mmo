defmodule AgentMmo.BenchmarkRun do
  use Ecto.Schema
  import Ecto.Changeset

  schema "benchmark_runs" do
    field :scenario,    :string
    field :score,       :integer
    field :steps,       :integer
    field :duration_ms, :integer

    belongs_to :api_key, AgentMmo.ApiKey

    # inserted_at is named completed_at per migration
    timestamps(type: :utc_datetime, updated_at: false, inserted_at: :completed_at)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:api_key_id, :scenario, :score, :steps, :duration_ms])
    |> validate_required([:api_key_id, :scenario, :score, :steps, :duration_ms])
    |> assoc_constraint(:api_key)
  end
end
