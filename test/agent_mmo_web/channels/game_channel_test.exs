defmodule AgentMmoWeb.GameChannelTest do
  use AgentMmoWeb.ChannelCase

  alias AgentMmoWeb.{GameChannel, UserSocket}
  alias AgentMmo.Auth

  setup do
    zone_id = "test_zone_channel_#{System.unique_integer([:positive])}"

    # Start a ZoneSupervisor for the test zone
    {:ok, _} = start_supervised({AgentMmo.World.ZoneSupervisor, zone_id: zone_id})

    # Issue a real API key for the test
    {:ok, {plaintext, _api_key}} = Auth.issue_key(%{"agent_name" => "test-agent", "owner" => "test@example.com"})

    {:ok, socket} = connect(UserSocket, %{"api_key" => plaintext})
    {:ok, socket: socket, zone_id: zone_id}
  end

  # ---- Join handshake (protocol version negotiation) ----

  test "join with valid protocol_version returns ok", %{socket: socket, zone_id: zone_id} do
    {:ok, reply, _socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    assert reply.status == "ok"
    assert reply.protocol_version == "1.0"
    assert Map.has_key?(reply, :player_id)
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

  # ---- action:move ----

  test "handle_in action:move returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:move", %{"direction" => "north", "seq" => 1})
    assert_reply ref, :ok, %{acked: true}
  end

  test "action:move with invalid direction returns INVALID_DIRECTION", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:move", %{"direction" => "diagonal-up", "seq" => 2})
    assert_reply ref, :error, %{code: "INVALID_DIRECTION"}
  end

  test "action:move missing direction returns MISSING_DIRECTION", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:move", %{"seq" => 3})
    assert_reply ref, :error, %{code: "MISSING_DIRECTION"}
  end

  test "action:move accepts all 8 cardinal/intercardinal directions", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    directions = ~w(north south east west northeast northwest southeast southwest)

    for direction <- directions do
      ref = push(socket, "action:move", %{"direction" => direction})
      assert_reply ref, :ok, %{acked: true}
    end
  end

  # ---- action:speak ----

  test "action:speak with target returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:speak", %{"target" => "npc_barkeep"})
    assert_reply ref, :ok, %{acked: true}
  end

  test "action:speak without target returns MISSING_TARGET", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:speak", %{})
    assert_reply ref, :error, %{code: "MISSING_TARGET"}
  end

  # ---- action:enter ----

  test "action:enter with target returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:enter", %{"target" => "exit_north"})
    assert_reply ref, :ok, %{acked: true}
  end

  test "action:enter without target returns MISSING_TARGET", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:enter", %{})
    assert_reply ref, :error, %{code: "MISSING_TARGET"}
  end

  # ---- action:wait / action:look / action:inventory / action:quests / action:flee ----

  test "action:wait returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:wait", %{})
    assert_reply ref, :ok, %{acked: true}
  end

  test "action:look returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:look", %{})
    assert_reply ref, :ok, %{acked: true}
  end

  test "action:inventory returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:inventory", %{})
    assert_reply ref, :ok, %{acked: true}
  end

  test "action:quests returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:quests", %{})
    assert_reply ref, :ok, %{acked: true}
  end

  test "action:flee returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:flee", %{})
    assert_reply ref, :ok, %{acked: true}
  end

  # ---- action:examine / pickup / drop / use / attack ----

  test "action:examine with target returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:examine", %{"target" => "npc_barkeep"})
    assert_reply ref, :ok, %{acked: true}
  end

  test "action:examine without target returns MISSING_TARGET", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:examine", %{})
    assert_reply ref, :error, %{code: "MISSING_TARGET"}
  end

  test "action:pickup with target returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:pickup", %{"target" => "item_key"})
    assert_reply ref, :ok, %{acked: true}
  end

  test "action:pickup without target returns MISSING_TARGET", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:pickup", %{})
    assert_reply ref, :error, %{code: "MISSING_TARGET"}
  end

  test "action:drop with item returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:drop", %{"item" => "health_potion"})
    assert_reply ref, :ok, %{acked: true}
  end

  test "action:drop without item returns MISSING_ITEM", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:drop", %{})
    assert_reply ref, :error, %{code: "MISSING_ITEM"}
  end

  test "action:use with item returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:use", %{"item" => "health_potion"})
    assert_reply ref, :ok, %{acked: true}
  end

  test "action:use without item returns MISSING_ITEM", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:use", %{})
    assert_reply ref, :error, %{code: "MISSING_ITEM"}
  end

  test "action:attack with target returns acked", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:attack", %{"target" => "enemy_thug"})
    assert_reply ref, :ok, %{acked: true}
  end

  test "action:attack without target returns MISSING_TARGET", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:attack", %{})
    assert_reply ref, :error, %{code: "MISSING_TARGET"}
  end

  test "action:reply without choice returns MISSING_CHOICE", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    ref = push(socket, "action:reply", %{})
    assert_reply ref, :error, %{code: "MISSING_CHOICE"}
  end

  # ---- Tick broadcast (regression canary) ----

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

  test "tick payload conforms to PROTOCOL.md schema", %{socket: socket, zone_id: zone_id} do
    {:ok, _, _socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    assert_push "tick", payload, 2000

    # Required top-level fields per PROTOCOL.md §5.1
    assert is_integer(payload.tick) and payload.tick >= 0
    assert is_integer(payload.timestamp_ms) and payload.timestamp_ms > 0
    assert is_binary(payload.zone_id)
    assert is_map(payload.zone)
    assert is_binary(payload.zone.id)
    assert is_integer(payload.zone.width) and payload.zone.width > 0
    assert is_integer(payload.zone.height) and payload.zone.height > 0
    assert is_map(payload.position)
    assert is_integer(payload.position.x)
    assert is_integer(payload.position.y)
    assert is_list(payload.entities)
    assert is_list(payload.inventory)
    assert is_list(payload.quest_log)
    assert is_integer(payload.score)
    assert is_integer(payload.steps)
    assert is_list(payload.events)
    assert is_list(payload.acked_seqs)
  end

  test "tick entity objects have required fields per PROTOCOL.md §5.1.1", %{socket: socket, zone_id: zone_id} do
    {:ok, _, _socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    assert_push "tick", payload, 2000

    # If there are entities, each must have the required fields
    for entity <- payload.entities do
      assert is_binary(entity.type)
      assert entity.type in ["player", "npc", "enemy", "item", "exit"]
      assert is_binary(entity.id)
      assert is_binary(entity.name)
      assert is_map(entity.position)
      assert is_integer(entity.position.x)
      assert is_integer(entity.position.y)
      assert is_float(entity.distance) or is_integer(entity.distance)
    end
  end

  test "move seq is echoed in acked_seqs on next tick", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    seq = 99
    ref = push(socket, "action:move", %{"direction" => "north", "seq" => seq})
    assert_reply ref, :ok, %{acked: true}

    # The next tick should contain our seq in acked_seqs
    assert_push "tick", payload, 2000
    assert seq in payload.acked_seqs
  end

  # ---- Run transcript recording ----

  test "completing a quest writes one RunTranscript row per recorded tick", %{socket: socket, zone_id: zone_id} do
    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "zone:#{zone_id}", %{
        "protocol_version" => "1.0"
      })

    # Push an action so the channel has a pending_action to pair with the next tick.
    ref = push(socket, "action:move", %{"direction" => "north", "seq" => 1})
    assert_reply ref, :ok, %{acked: true}

    # Wait for at least one tick to arrive at the channel so the buffer is populated.
    assert_push "tick", _payload, 2000

    # Simulate quest_complete arriving at the channel process (the same path
    # ZoneTicker uses when a player finishes a quest).
    send(socket.channel_pid, {:player_event, %{
      type: "quest_complete",
      quest_id: "q",
      final_score: 5,
      steps_taken: 1
    }})

    # Wait for the channel to handle the event and flush transcripts.
    assert_push "quest_complete", _payload, 2000

    [run] = AgentMmo.Repo.all(AgentMmo.BenchmarkRun)
    transcripts = AgentMmo.RunTranscripts.list_for_run(run.id)
    assert length(transcripts) >= 1
    assert hd(transcripts).action["action"] == "move"
  end
end
