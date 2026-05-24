defmodule AgentMmo.SpectateTracker do
  @moduledoc """
  GenServer that tracks in-flight benchmark runs and maintains a ranked snapshot
  of the current top agent for homepage hero display.

  It subscribes to `zone:*` PubSub broadcasts and `leaderboard:*` events.
  Active runs are tracked by player_id -> snapshot. The top run (highest current
  score) is published on `spectate:lobby` so SpectateChannel can forward to
  unauthenticated spectators.

  Run lifecycle:
    - Started: when a player joins a zone (via broadcast `{:run_started, player_id, meta}`)
    - Ticked:  each zone tick updates score/steps/zone for that player
    - Ended:   quest_complete event or disconnect broadcasts `{:run_ended, player_id}`
  """

  use GenServer

  require Logger

  @pubsub AgentMmo.PubSub

  defstruct runs: %{}, top_player_id: nil

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Return the current top run snapshot (or nil)."
  def current_run do
    case GenServer.call(__MODULE__, :current_run) do
      {:ok, run} -> run
      :none -> nil
    end
  end

  @doc "Return all active run snapshots, ranked by score desc."
  def ranked_runs(limit \\ 10) do
    GenServer.call(__MODULE__, {:ranked_runs, limit})
  end

  @doc "Notify the tracker a new run has started."
  def run_started(player_id, meta) do
    GenServer.cast(__MODULE__, {:run_started, player_id, meta})
  end

  @doc "Notify the tracker a run has ended."
  def run_ended(player_id) do
    GenServer.cast(__MODULE__, {:run_ended, player_id})
  end

  @doc "Clear all tracked runs. Intended for test isolation."
  def reset, do: GenServer.call(__MODULE__, :reset)

  # --- Server callbacks ---

  @impl true
  def init(_opts) do
    # Subscribe to lobby-level spectator broadcasts and zone wildcards via PubSub
    Phoenix.PubSub.subscribe(@pubsub, "tracker:runs")
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %__MODULE__{}}
  end

  def handle_call(:current_run, _from, %{top_player_id: nil} = state) do
    {:reply, :none, state}
  end

  def handle_call(:current_run, _from, %{top_player_id: top, runs: runs} = state) do
    case Map.get(runs, top) do
      nil -> {:reply, :none, state}
      run -> {:reply, {:ok, run}, state}
    end
  end

  def handle_call({:ranked_runs, limit}, _from, %{runs: runs} = state) do
    ranked =
      runs
      |> Map.values()
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(limit)

    {:reply, ranked, state}
  end

  @impl true
  def handle_cast({:run_started, player_id, meta}, state) do
    run = %{
      player_id: player_id,
      agent_name: Map.get(meta, :agent_name, player_id),
      scenario: Map.get(meta, :scenario, "unknown"),
      zone_id: Map.get(meta, :zone_id, "tavern"),
      score: 100,
      steps: 0,
      started_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    new_runs = Map.put(state.runs, player_id, run)
    new_state = %{state | runs: new_runs} |> recompute_top()
    broadcast_current(new_state)
    {:noreply, new_state}
  end

  def handle_cast({:run_ended, player_id}, state) do
    new_runs = Map.delete(state.runs, player_id)
    new_state = %{state | runs: new_runs} |> recompute_top()
    broadcast_current(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:tick_update, player_id, score, steps, zone_id}, state) do
    case Map.get(state.runs, player_id) do
      nil ->
        {:noreply, state}

      run ->
        updated = %{run | score: score, steps: steps, zone_id: zone_id}
        new_runs = Map.put(state.runs, player_id, updated)
        new_state = %{state | runs: new_runs} |> recompute_top()
        broadcast_current(new_state)
        {:noreply, new_state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("SpectateTracker unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # --- Private ---

  defp recompute_top(%{runs: runs} = state) when map_size(runs) == 0 do
    %{state | top_player_id: nil}
  end

  defp recompute_top(%{runs: runs} = state) do
    top =
      runs
      |> Enum.max_by(fn {_pid, r} -> r.score end)
      |> elem(0)

    %{state | top_player_id: top}
  end

  defp broadcast_current(%{top_player_id: nil}) do
    Phoenix.PubSub.broadcast(@pubsub, "spectate:lobby", {:spectate_update, nil})
  end

  defp broadcast_current(%{top_player_id: top, runs: runs}) do
    run = Map.get(runs, top)
    Phoenix.PubSub.broadcast(@pubsub, "spectate:lobby", {:spectate_update, run})
  end
end
