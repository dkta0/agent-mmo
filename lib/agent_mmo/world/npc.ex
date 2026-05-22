defmodule AgentMmo.World.NPC do
  @moduledoc "GenServer for a single NPC instance, tracking per-player dialogue state."

  use GenServer

  defstruct [:id, :name, :position, :zone_id, :dialogue, dialogue_states: %{}]

  # Client API

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_name(id))
  end

  def speak(npc_id, player_id) do
    case Registry.lookup(AgentMmo.ZoneRegistry, {:npc, npc_id}) do
      [{pid, _}] -> GenServer.call(pid, {:speak, player_id})
      [] -> {:error, "NPC not found"}
    end
  end

  def reply(npc_id, player_id, choice_id) do
    case Registry.lookup(AgentMmo.ZoneRegistry, {:npc, npc_id}) do
      [{pid, _}] -> GenServer.call(pid, {:reply, player_id, choice_id})
      [] -> {:error, "NPC not found"}
    end
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      name: Keyword.get(opts, :name, "NPC"),
      position: Keyword.get(opts, :position, {0, 0}),
      zone_id: Keyword.get(opts, :zone_id, ""),
      dialogue: Keyword.fetch!(opts, :dialogue),
      dialogue_states: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:speak, player_id}, _from, state) do
    dialogue = state.dialogue
    choices = Enum.map(dialogue.choices, fn c -> %{id: c.id, text: c.text} end)
    response = %{greeting: dialogue.greeting, choices: choices}

    new_states = Map.put(state.dialogue_states, player_id, :waiting_reply)
    {:reply, {:ok, response}, %{state | dialogue_states: new_states}}
  end

  def handle_call({:reply, player_id, choice_id}, _from, state) do
    case Map.get(state.dialogue_states, player_id) do
      :waiting_reply ->
        case Enum.find(state.dialogue.choices, fn c -> c.id == choice_id or to_string(c.id) == to_string(choice_id) end) do
          nil ->
            {:reply, {:error, "invalid_choice"}, state}

          choice ->
            new_states = Map.put(state.dialogue_states, player_id, :idle)
            flags = choice[:flags] || []
            {:reply, {:ok, %{text: choice.response}, flags}, %{state | dialogue_states: new_states}}
        end

      _ ->
        {:reply, {:error, "not_in_dialogue"}, state}
    end
  end

  defp via_name(npc_id) do
    {:via, Registry, {AgentMmo.ZoneRegistry, {:npc, npc_id}}}
  end
end
