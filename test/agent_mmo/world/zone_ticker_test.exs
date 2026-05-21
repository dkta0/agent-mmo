defmodule AgentMmo.World.ZoneTickerTest do
  use ExUnit.Case, async: false

  alias AgentMmo.World.{ZoneSupervisor, ZoneTicker, Entity}

  @test_zone "test_zone_ticker_#{:rand.uniform(10_000)}"

  setup do
    # Start a fresh ZoneSupervisor for this test
    zone_id = "#{@test_zone}_#{System.unique_integer([:positive])}"

    {:ok, _} = start_supervised({ZoneSupervisor, zone_id: zone_id})
    Phoenix.PubSub.subscribe(AgentMmo.PubSub, "zone:#{zone_id}")

    {:ok, zone_id: zone_id}
  end

  test "tick loop fires within 1s", %{zone_id: zone_id} do
    assert_receive {:tick_broadcast, payload}, 1000
    assert payload.zone_id == zone_id
    assert payload.tick >= 1
    assert is_integer(payload.timestamp_ms)
    assert is_list(payload.entities)
  end

  test "movement action applied on tick", %{zone_id: zone_id} do
    player_id = "test_player_move"

    entity = %Entity{
      id: "player_#{player_id}",
      kind: :player,
      position: {5, 5},
      zone_id: zone_id,
      health: 100,
      max_health: 100,
      state: %{display_name: "Tester", level: 1, animation: "idle"},
      updated_at: 0
    }

    ZoneSupervisor.join(zone_id, player_id, entity)
    ZoneTicker.enqueue_action(zone_id, player_id, %{"action" => "move", "direction" => "north", "seq" => 1})

    # Wait for 2 ticks
    assert_receive {:tick_broadcast, _}, 1500
    assert_receive {:tick_broadcast, _}, 1500

    entities = ZoneSupervisor.entity_state(zone_id)
    player = Enum.find(entities, fn e -> e.id == "player_#{player_id}" end)

    assert player != nil
    {_x, y} = player.position
    assert y == 4
  end

  test "movement blocked at boundary 0,0 moving north", %{zone_id: zone_id} do
    player_id = "test_player_boundary"

    entity = %Entity{
      id: "player_#{player_id}",
      kind: :player,
      position: {0, 0},
      zone_id: zone_id,
      health: 100,
      max_health: 100,
      state: %{display_name: "Boundary", level: 1, animation: "idle"},
      updated_at: 0
    }

    ZoneSupervisor.join(zone_id, player_id, entity)
    ZoneTicker.enqueue_action(zone_id, player_id, %{"action" => "move", "direction" => "north", "seq" => 1})

    assert_receive {:tick_broadcast, _}, 1500
    assert_receive {:tick_broadcast, _}, 1500

    entities = ZoneSupervisor.entity_state(zone_id)
    player = Enum.find(entities, fn e -> e.id == "player_#{player_id}" end)

    assert player != nil
    assert player.position == {0, 0}
  end
end
