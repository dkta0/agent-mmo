defmodule AgentMmo.Player.PlayerSession do
  @moduledoc "GenServer representing a single connected player's session."

  use GenServer, restart: :temporary

  alias AgentMmo.World.{Entity, ZoneSupervisor}

  defstruct [:player_id, :account_id, :current_zone_id, :socket_pid]

  def start_link(opts) do
    player_id = Keyword.fetch!(opts, :player_id)
    GenServer.start_link(__MODULE__, opts, name: via_name(player_id))
  end

  @impl true
  def init(opts) do
    player_id = Keyword.fetch!(opts, :player_id)
    zone_id = Keyword.get(opts, :zone_id, "overworld_0_0")
    socket_pid = Keyword.get(opts, :socket_pid)

    entity = %Entity{
      id: "player_#{player_id}",
      kind: :player,
      position: {0, 0},
      zone_id: zone_id,
      health: 100,
      max_health: 100,
      state: %{display_name: player_id, level: 1, animation: "idle"},
      updated_at: 0
    }

    ZoneSupervisor.join(zone_id, player_id, entity)

    state = %__MODULE__{
      player_id: player_id,
      account_id: nil,
      current_zone_id: zone_id,
      socket_pid: socket_pid
    }

    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    ZoneSupervisor.leave(state.current_zone_id, state.player_id)
    :ok
  end

  defp via_name(player_id) do
    {:via, Registry, {AgentMmo.ZoneRegistry, {:player_session, player_id}}}
  end
end
