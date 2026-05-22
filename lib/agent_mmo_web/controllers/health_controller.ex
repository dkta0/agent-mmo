defmodule AgentMmoWeb.HealthController do
  use AgentMmoWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
