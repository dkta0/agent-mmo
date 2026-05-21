defmodule AgentMmo.World.ZoneNPCSup do
  @moduledoc "DynamicSupervisor for NPC processes in a zone. Placeholder for now."

  use DynamicSupervisor

  def start_link(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    DynamicSupervisor.start_link(__MODULE__, opts, name: via_name(zone_id))
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp via_name(zone_id) do
    {:via, Registry, {AgentMmo.ZoneRegistry, {:npc_sup, zone_id}}}
  end
end
