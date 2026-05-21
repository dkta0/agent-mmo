defmodule AgentMmo.Repo do
  use Ecto.Repo,
    otp_app: :agent_mmo,
    adapter: Ecto.Adapters.Postgres
end
