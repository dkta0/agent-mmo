defmodule AgentMmo.Player.PlayerSession do
  @moduledoc "GenServer representing a single connected player's session."

  use GenServer, restart: :temporary

  alias AgentMmo.World.{Entity, ZoneSupervisor}

  defstruct [
    :player_id,
    :account_id,
    :current_zone_id,
    :socket_pid,
    inventory: [],
    quests: [],
    flags: [],
    score: 100,
    steps: 0
  ]

  # Client API

  def start_link(opts) do
    player_id = Keyword.fetch!(opts, :player_id)
    GenServer.start_link(__MODULE__, opts, name: via_name(player_id))
  end

  def get_state(player_id) do
    case Registry.lookup(AgentMmo.ZoneRegistry, {:player_session, player_id}) do
      [{pid, _}] -> GenServer.call(pid, :get_state)
      [] -> {:error, :not_found}
    end
  end

  def add_flag(player_id, flag) do
    GenServer.cast(via_name(player_id), {:add_flag, flag})
  end

  def add_item(player_id, item_id) do
    GenServer.cast(via_name(player_id), {:add_item, item_id})
  end

  def remove_item(player_id, item_id) do
    GenServer.call(via_name(player_id), {:remove_item, item_id})
  end

  def deduct_score(player_id, amount, reason) do
    GenServer.call(via_name(player_id), {:deduct_score, amount, reason})
  end

  def increment_steps(player_id) do
    GenServer.call(via_name(player_id), :increment_steps)
  end

  def update_zone(player_id, zone_id) do
    GenServer.cast(via_name(player_id), {:update_zone, zone_id})
  end

  def complete_quest(player_id, quest_id) do
    GenServer.cast(via_name(player_id), {:complete_quest, quest_id})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    player_id = Keyword.fetch!(opts, :player_id)
    zone_id = Keyword.get(opts, :zone_id, "tavern")
    socket_pid = Keyword.get(opts, :socket_pid)

    entity = %Entity{
      id: "player_#{player_id}",
      kind: :player,
      position: {3, 3},
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
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:remove_item, item_id}, _from, state) do
    if item_id in state.inventory do
      {:reply, :ok, %{state | inventory: List.delete(state.inventory, item_id)}}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:deduct_score, amount, _reason}, _from, state) do
    new_score = max(0, state.score - amount)
    {:reply, new_score, %{state | score: new_score}}
  end

  def handle_call(:increment_steps, _from, state) do
    new_steps = state.steps + 1
    {:reply, new_steps, %{state | steps: new_steps}}
  end

  @impl true
  def handle_cast({:add_flag, flag}, state) do
    flags =
      if flag in state.flags do
        state.flags
      else
        [flag | state.flags]
      end

    {:noreply, %{state | flags: flags}}
  end

  def handle_cast({:add_item, item_id}, state) do
    {:noreply, %{state | inventory: [item_id | state.inventory]}}
  end

  def handle_cast({:update_zone, zone_id}, state) do
    {:noreply, %{state | current_zone_id: zone_id}}
  end

  def handle_cast({:complete_quest, quest_id}, state) do
    quests =
      Enum.map(state.quests, fn q ->
        if q.quest_id == quest_id do
          %{q | completed: true}
        else
          q
        end
      end)

    {:noreply, %{state | quests: quests}}
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
