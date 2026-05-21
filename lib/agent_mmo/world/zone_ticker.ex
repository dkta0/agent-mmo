defmodule AgentMmo.World.ZoneTicker do
  @moduledoc "GenServer driving the 500ms tick loop for a zone."

  use GenServer

  alias AgentMmo.World.Entity

  @default_tick_interval_ms 500
  @map_max 99
  @map_min 0

  defstruct [:zone_id, :tick, :action_queues, :tick_interval_ms]

  # Client API

  def start_link(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    GenServer.start_link(__MODULE__, opts, name: via_name(zone_id))
  end

  @doc "Enqueue a player action to be processed on the next tick."
  def enqueue_action(zone_id, player_id, action) do
    GenServer.cast(via_name(zone_id), {:enqueue_action, player_id, action})
  end

  defp via_name(zone_id) do
    {:via, Registry, {AgentMmo.ZoneRegistry, {:ticker, zone_id}}}
  end

  # Server callbacks

  @impl true
  def init(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    interval = Application.get_env(:agent_mmo, :tick_interval_ms, @default_tick_interval_ms)

    state = %__MODULE__{
      zone_id: zone_id,
      tick: 0,
      action_queues: %{},
      tick_interval_ms: interval
    }

    schedule_tick(interval)
    {:ok, state}
  end

  @impl true
  def handle_cast({:enqueue_action, player_id, action}, state) do
    queue = Map.get(state.action_queues, player_id, [])
    {:noreply, %{state | action_queues: Map.put(state.action_queues, player_id, queue ++ [action])}}
  end

  @impl true
  def handle_info(:tick, state) do
    {new_state, acked_seqs} = process_tick(state)
    schedule_tick(state.tick_interval_ms)
    broadcast_tick(new_state, acked_seqs)
    {:noreply, new_state}
  end

  defp process_tick(state) do
    ets_table = ets_name(state.zone_id)
    entities = read_entities(ets_table)

    {updated_entities, all_acked} =
      Enum.reduce(state.action_queues, {entities, []}, fn {player_id, actions}, {ents, acked} ->
        {new_ents, new_acked} = apply_player_actions(ents, player_id, actions, state.zone_id)
        {new_ents, acked ++ new_acked}
      end)

    new_tick = state.tick + 1

    Enum.each(updated_entities, fn entity ->
      :ets.insert(ets_table, {{entity.kind, entity.id}, %{entity | updated_at: new_tick}})
    end)

    new_state = %{state | tick: new_tick, action_queues: %{}}
    {new_state, all_acked}
  end

  defp apply_player_actions(entities, player_id, actions, zone_id) do
    player_key = "player_#{player_id}"

    {updated_entities, acked} =
      Enum.reduce(actions, {entities, []}, fn action, {ents, acked} ->
        case action do
          %{"action" => "move", "direction" => dir, "seq" => seq} ->
            new_ents = move_player(ents, player_key, dir, zone_id)
            {new_ents, [seq | acked]}

          %{"action" => "move", "direction" => dir} ->
            new_ents = move_player(ents, player_key, dir, zone_id)
            {new_ents, acked}

          _ ->
            {ents, acked}
        end
      end)

    {updated_entities, Enum.reverse(acked)}
  end

  defp move_player(entities, player_id, direction, zone_id) do
    Enum.map(entities, fn entity ->
      if entity.id == player_id and entity.kind == :player and entity.zone_id == zone_id do
        {x, y} = entity.position
        {dx, dy} = direction_delta(direction)
        new_x = clamp(x + dx)
        new_y = clamp(y + dy)
        %{entity | position: {new_x, new_y}}
      else
        entity
      end
    end)
  end

  defp direction_delta("north"), do: {0, -1}
  defp direction_delta("south"), do: {0, 1}
  defp direction_delta("east"), do: {1, 0}
  defp direction_delta("west"), do: {-1, 0}
  defp direction_delta("northeast"), do: {1, -1}
  defp direction_delta("northwest"), do: {-1, -1}
  defp direction_delta("southeast"), do: {1, 1}
  defp direction_delta("southwest"), do: {-1, 1}
  defp direction_delta(_), do: {0, 0}

  defp clamp(v), do: max(@map_min, min(@map_max, v))

  defp read_entities(ets_table) do
    case :ets.whereis(ets_table) do
      :undefined ->
        []

      _ ->
        :ets.tab2list(ets_table)
        |> Enum.filter(fn {key, _} -> key != :zone_meta end)
        |> Enum.map(fn {_key, entity} -> entity end)
    end
  end

  defp broadcast_tick(state, acked_seqs) do
    entities =
      read_entities(ets_name(state.zone_id))
      |> Enum.map(&Entity.to_json/1)

    payload = %{
      tick: state.tick,
      timestamp_ms: System.os_time(:millisecond),
      zone_id: state.zone_id,
      entities: entities,
      events: [],
      acked_seqs: acked_seqs
    }

    Phoenix.PubSub.broadcast(AgentMmo.PubSub, "zone:#{state.zone_id}", {:tick_broadcast, payload})
  end

  defp schedule_tick(interval), do: Process.send_after(self(), :tick, interval)

  defp ets_name(zone_id), do: :"zone_entities_#{zone_id}"
end
