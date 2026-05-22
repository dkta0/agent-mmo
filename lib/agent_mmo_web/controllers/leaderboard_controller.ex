defmodule AgentMmoWeb.LeaderboardController do
  use AgentMmoWeb, :controller

  alias AgentMmo.Leaderboard

  def index(conn, %{"scenario" => scenario} = params) do
    limit =
      case Integer.parse(Map.get(params, "limit", "50")) do
        {n, _} -> min(n, 100)
        :error -> 50
      end

    entries = Leaderboard.top_scores(scenario, limit)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    ranked =
      entries
      |> Enum.with_index(1)
      |> Enum.map(fn {e, rank} -> Map.put(e, :rank, rank) end)

    conn
    |> put_status(200)
    |> json(%{scenario: scenario, entries: ranked, generated_at: now})
  end

  def index(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "scenario parameter is required"})
  end
end
