defmodule AgentMmo.RunTranscripts do
  @moduledoc "Per-(action,tick) transcript writes during a benchmark run."

  import Ecto.Query
  alias AgentMmo.{Repo, RunTranscript}

  @doc "Append one transcript row. `attrs` must include `:action` and `:tick` maps."
  def append(benchmark_run_id, tick_no, %{action: action, tick: tick}) do
    %RunTranscript{}
    |> RunTranscript.changeset(%{
      benchmark_run_id: benchmark_run_id,
      tick_no: tick_no,
      action: action,
      tick: tick
    })
    |> Repo.insert()
  end

  @doc "Return all transcript rows for a run, ordered by tick_no asc."
  def list_for_run(benchmark_run_id) do
    Repo.all(
      from t in RunTranscript,
        where: t.benchmark_run_id == ^benchmark_run_id,
        order_by: [asc: t.tick_no]
    )
  end
end
