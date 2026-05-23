defmodule AgentMmoWeb.SpectateChannelTest do
  use AgentMmoWeb.ChannelCase

  alias AgentMmoWeb.SpectatorSocket

  describe "join spectate:lobby" do
    test "joins successfully without auth" do
      {:ok, _, socket} =
        socket(SpectatorSocket, nil, %{})
        |> subscribe_and_join("spectate:lobby", %{})

      assert socket.assigns.zone_id == "lobby"
    end

    test "join reply includes current_run key" do
      {:ok, reply, _socket} =
        socket(SpectatorSocket, nil, %{})
        |> subscribe_and_join("spectate:lobby", %{})

      assert Map.has_key?(reply, :current_run)
    end

    test "get:current_run event returns run info" do
      {:ok, _reply, socket} =
        socket(SpectatorSocket, nil, %{})
        |> subscribe_and_join("spectate:lobby", %{})

      ref = push(socket, "get:current_run", %{})
      assert_reply ref, :ok, %{run: _}
    end

    test "get:ranked_runs event returns runs list" do
      {:ok, _reply, socket} =
        socket(SpectatorSocket, nil, %{})
        |> subscribe_and_join("spectate:lobby", %{})

      ref = push(socket, "get:ranked_runs", %{})
      assert_reply ref, :ok, %{runs: _}
    end

    test "action messages are rejected" do
      {:ok, _reply, socket} =
        socket(SpectatorSocket, nil, %{})
        |> subscribe_and_join("spectate:lobby", %{})

      ref = push(socket, "action:move", %{"direction" => "north"})
      assert_reply ref, :error, %{reason: "spectate_channel_read_only"}
    end

    test "spectate_update broadcast is forwarded to client" do
      {:ok, _reply, _socket} =
        socket(SpectatorSocket, nil, %{})
        |> subscribe_and_join("spectate:lobby", %{})

      run = %{player_id: "p1", agent_name: "test-bot", score: 200, steps: 5, zone_id: "cave", scenario: "trial", started_at: "now"}
      Phoenix.PubSub.broadcast(AgentMmo.PubSub, "spectate:lobby", {:spectate_update, run})

      assert_push "current_run", %{run: pushed_run}
      assert pushed_run.player_id == "p1"
    end
  end
end
