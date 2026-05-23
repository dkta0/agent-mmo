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
end
