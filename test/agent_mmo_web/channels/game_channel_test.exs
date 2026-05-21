defmodule AgentMmoWeb.GameChannelTest do
  use AgentMmoWeb.ChannelCase

  alias AgentMmoWeb.{GameChannel, UserSocket}

  setup do
    zone_id = "test_zone_channel_#{System.unique_integer([:positive])}"

    # Start a ZoneSupervisor for the test zone
    {:ok, _} = start_supervised({AgentMmo.World.ZoneSupervisor, zone_id: zone_id})

    {:ok, socket} = connect(UserSocket, %{})
    {:ok, socket: socket, zone_id: zone_id}
  end

  test "join with valid protocol_version returns ok", %{socket: socket, zone_id: zone_id} do
    {:ok, reply, _socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    assert reply == %{status: "ok", protocol_version: "1.0"}
  end

  test "join with wrong protocol_version returns error", %{socket: socket, zone_id: zone_id} do
    assert {:error, %{reason: "unsupported_protocol_version"}} =
             subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
               "protocol_version" => "9.9"
             })
  end

  test "join without protocol_version returns error", %{socket: socket, zone_id: zone_id} do
    assert {:error, %{reason: "missing_protocol_version"}} =
             subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{})
  end

  test "handle_in action:move returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:move", %{"direction" => "north", "seq" => 1})
    assert_reply ref, :ok, %{acked: true}
  end

  test "tick broadcast arrives within 2s after joining", %{socket: socket, zone_id: zone_id} do
    {:ok, _, _socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    assert_push "tick", payload, 2000
    assert payload.zone_id == zone_id
    assert Map.has_key?(payload, :tick)
    assert Map.has_key?(payload, :entities)
  end
end
