defmodule AgentMmo.Runs do
  @moduledoc "Context for recording and querying game runs."

  alias AgentMmo.{Repo, Run}

  @doc """
  Record a completed run.

  Attrs:
    - scenario (string, required)
    - score (integer >= 0, required)
    - ranked (boolean, optional, default false)
    - user_id (integer, optional)
    - completed_at (utc_datetime, optional — defaults to now)

  Returns {:ok, %Run{}} | {:error, changeset}.
  """
  def record_run(attrs) do
    attrs =
      if Map.has_key?(attrs, "completed_at") and attrs["completed_at"] != nil do
        attrs
      else
        Map.put(attrs, "completed_at", DateTime.utc_now() |> DateTime.truncate(:second))
      end

    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Returns the 10 most recent runs for a given user_id."
  def list_recent_runs_for_user(user_id) do
    import Ecto.Query
    Repo.all(
      from r in Run,
        where: r.user_id == ^user_id,
        order_by: [desc: r.completed_at],
        limit: 10
    )
  end
end
