defmodule AgentMmoWeb.PageController do
  use AgentMmoWeb, :controller

  alias AgentMmo.Leaderboard

  def home(conn, _params) do
    entries = Leaderboard.top_scores("missing_apprentice", 5)
    render(conn, :home, entries: entries)
  end
end
