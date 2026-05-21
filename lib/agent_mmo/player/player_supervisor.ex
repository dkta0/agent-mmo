defmodule AgentMmo.Player.PlayerSupervisor do
  @moduledoc "DynamicSupervisor for PlayerSession processes."

  use DynamicSupervisor

  alias AgentMmo.Player.PlayerSession

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a PlayerSession for the given player_id."
  def start_player(opts) do
    DynamicSupervisor.start_child(__MODULE__, {PlayerSession, opts})
  end

  @doc "Stop a PlayerSession for the given player_id."
  def stop_player(player_id) do
    case Registry.lookup(AgentMmo.ZoneRegistry, {:player_session, player_id}) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end
end
