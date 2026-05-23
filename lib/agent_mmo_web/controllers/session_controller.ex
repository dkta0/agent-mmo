defmodule AgentMmoWeb.SessionController do
  use AgentMmoWeb, :controller

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Logged out.")
    |> redirect(to: "/")
  end
end
