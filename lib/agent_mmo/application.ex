defmodule AgentMmo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    AgentMmo.Auth.init_cache()

    children = [
      AgentMmoWeb.Telemetry,
      AgentMmo.Repo,
      {DNSCluster, query: Application.get_env(:agent_mmo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AgentMmo.PubSub},
      {Registry, keys: :unique, name: AgentMmo.ZoneRegistry},
      {AgentMmo.Player.PlayerSupervisor, []},
      {DynamicSupervisor, name: AgentMmo.ZoneDynamicSup, strategy: :one_for_one},
      {AgentMmo.World.ScenarioLoader, []},
      {AgentMmo.World.ZoneSupervisor, zone_id: "overworld_0_0"},
      # Start to serve requests, typically the last entry
      AgentMmoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AgentMmo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AgentMmoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
