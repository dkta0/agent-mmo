defmodule AgentMmoWeb.RunController do
  use AgentMmoWeb, :controller

  alias AgentMmo.Runs

  @doc """
  POST /api/runs
  Body: { scenario, score, ranked (optional, default false) }
  Auth: optional — user_id may be supplied in params but is not required.
  Returns: { run_id }
  """
  def create(conn, params) do
    attrs = %{
      "scenario" => params["scenario"],
      "score" => params["score"],
      "ranked" => Map.get(params, "ranked", false),
      "user_id" => Map.get(params, "user_id")
    }

    case Runs.record_run(attrs) do
      {:ok, run} ->
        conn
        |> put_status(201)
        |> json(%{run_id: run.id})

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, val}, acc ->
              String.replace(acc, "%{#{key}}", to_string(val))
            end)
          end)

        conn
        |> put_status(422)
        |> json(%{errors: errors})
    end
  end

  def transcript(conn, %{"id" => id}) do
    case Integer.parse(id) do
      {run_id, _} ->
        entries =
          AgentMmo.RunTranscripts.list_for_run(run_id)
          |> Enum.map(&Map.take(&1, [:tick_no, :action, :tick, :inserted_at]))

        conn
        |> put_status(200)
        |> json(%{run_id: run_id, transcript: entries})

      :error ->
        conn
        |> put_status(400)
        |> json(%{error: "invalid run id"})
    end
  end
end
