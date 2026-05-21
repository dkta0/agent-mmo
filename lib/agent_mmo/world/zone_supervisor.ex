defmodule AgentMmo.World.ZoneSupervisor do
  @moduledoc "Supervises ZoneTicker and ZoneNPCSup for a single zone. Owns the ETS entity table."

  use Supervisor

  alias AgentMmo.World.{Entity, ZoneTicker, ZoneNPCSup}

  def start_link(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    Supervisor.start_link(__MODULE__, opts, name: via_name(zone_id))
  end

  @impl true
  def init(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    table_name = ets_name(zone_id)

    # Create ETS table owned by this supervisor
    :ets.new(table_name, [:set, :public, :named_table, {:read_concurrency, true}])

    # Seed zone meta
    :ets.insert(table_name, {:zone_meta, %{zone_id: zone_id, tick: 0}})

    children = [
      {ZoneTicker, zone_id: zone_id},
      {ZoneNPCSup, zone_id: zone_id}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc "Return all entity snapshots from ETS."
  def entity_state(zone_id) do
    table = ets_name(zone_id)

    case :ets.whereis(table) do
      :undefined ->
        []

      _ ->
        :ets.tab2list(table)
        |> Enum.filter(fn {key, _} -> key != :zone_meta end)
        |> Enum.map(fn {_key, entity} -> entity end)
    end
  end

  @doc "Add a player entity to the zone ETS table."
  def join(zone_id, _player_id, %Entity{} = entity) do
    :ets.insert(ets_name(zone_id), {{entity.kind, entity.id}, entity})
    :ok
  end

  @doc "Remove a player entity from the zone ETS table."
  def leave(zone_id, player_id) do
    :ets.delete(ets_name(zone_id), {:player, "player_#{player_id}"})
    :ok
  end

  defp via_name(zone_id) do
    {:via, Registry, {AgentMmo.ZoneRegistry, {:zone_sup, zone_id}}}
  end

  defp ets_name(zone_id), do: :"zone_entities_#{zone_id}"
end
