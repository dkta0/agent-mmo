# TavernBench Demo Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** A live, recordable demo where a real AI agent (Hermes) connects to TavernBench via Python SDK, reasons through an unfamiliar quest in real time, while a Go TUI shows every move as a spectator. The output is a tweetable video.

**Architecture:**
- `agent_mmo/` — private Elixir/Phoenix server. Zones, NPCs, quests, scoring, all actions.
- `agent-mmo/clients/python/` — public Python SDK. WebSocket client, clean action methods, state management.
- `agent-mmo/clients/tui/` — public Go TUI. Spectator view: 2D map, entity positions, action log, quest status.

**Tech Stack:** Elixir 1.14 + Phoenix 1.7, Python 3.10 + websockets 16.0, Go 1.22 + Bubbletea

**Repo split:**
- Server code stays in `agent_mmo/` (private)
- Client code lives in `agent-mmo/clients/` (public)

---

## The Demo Scenario: "The Missing Merchant"

A small tavern district. The agent must find a missing merchant by talking to NPCs, navigating two zones, and confronting the correct enemy.

### Map

```
Zone: tavern_hall (8x6)
┌────────────────┐
│  . . . . . . . │
│  . B . . . . . │  B = Barkeep (NPC)
│  . . . . . . . │
│  . . . P . . . │  P = Player spawn
│  . . . W . . . │  W = Wench (NPC)
│  . . . . . [N] │  [N] = exit north → alley
└────────────────┘

Zone: dark_alley (6x5)
┌──────────────┐
│  . . . . . . │
│  . T . . . . │  T = Thug (enemy, correct target)
│  . . . . . . │
│  . R . . . . │  R = Rat (enemy, wrong target — red herring)
│  [S] . . . . │  [S] = exit south → tavern_hall
└──────────────┘
```

### Quest: "Find the Missing Merchant"

**Objectives:**
1. Learn the merchant went north (speak to Barkeep or Wench)
2. Enter the alley
3. Slay the Thug (not the Rat)
4. Return south (quest auto-completes on zone exit after Thug is dead)

**Scoring:**
- Base: 100 points
- -5 per step taken
- -20 for attacking the Rat
- -10 for dying and respawning
- Bonus +20 if completed in ≤15 steps

**Dialogue trees:**

Barkeep:
- "What can I get ya?" →
  1. "Seen the merchant Aldric?" → "Aye, headed north into the alley, looking scared."
  2. "What's north of here?" → "Dark alley. Wouldn't go alone."
  3. "Nothing, thanks." → "Safe travels."

Wench:
- "Evening." →
  1. "Have you seen Aldric?" → "The merchant? Ran past me heading north. Something chased him."
  2. "What's in the alley?" → "Thugs and rats. Both dangerous, but one worse than the other."
  3. "Never mind." → "Suit yourself."

Thug (on examine): "A dangerous-looking thug. This must be who scared the merchant."
Rat (on examine): "A large rat. Unpleasant, but probably not responsible for the merchant's disappearance."

---

## Tasks

### Task 1: Implement remaining actions in GameChannel + ZoneTicker

**Objective:** Handle all actions beyond `move`: speak, reply, examine, pickup, attack, flee, inventory, quests, look, enter.

**Files:**
- Modify: `lib/agent_mmo_web/channels/game_channel.ex`
- Modify: `lib/agent_mmo/world/zone_ticker.ex`

**Step 1: Add action handlers to `game_channel.ex`**

```elixir
# speak
def handle_in("action:speak", %{"target" => target_id}, socket) do
  ZoneTicker.enqueue_action(socket.assigns.zone_id, socket.assigns.player_id,
    %{"action" => "speak", "target" => target_id})
  {:reply, {:ok, %{acked: true}}, socket}
end

# reply
def handle_in("action:reply", %{"choice" => choice}, socket) do
  ZoneTicker.enqueue_action(socket.assigns.zone_id, socket.assigns.player_id,
    %{"action" => "reply", "choice" => choice})
  {:reply, {:ok, %{acked: true}}, socket}
end

# examine
def handle_in("action:examine", %{"target" => target_id}, socket) do
  ZoneTicker.enqueue_action(socket.assigns.zone_id, socket.assigns.player_id,
    %{"action" => "examine", "target" => target_id})
  {:reply, {:ok, %{acked: true}}, socket}
end

# attack
def handle_in("action:attack", %{"target" => target_id}, socket) do
  ZoneTicker.enqueue_action(socket.assigns.zone_id, socket.assigns.player_id,
    %{"action" => "attack", "target" => target_id})
  {:reply, {:ok, %{acked: true}}, socket}
end

# flee
def handle_in("action:flee", _payload, socket) do
  ZoneTicker.enqueue_action(socket.assigns.zone_id, socket.assigns.player_id,
    %{"action" => "flee"})
  {:reply, {:ok, %{acked: true}}, socket}
end

# inventory
def handle_in("action:inventory", _payload, socket) do
  ZoneTicker.enqueue_action(socket.assigns.zone_id, socket.assigns.player_id,
    %{"action" => "inventory"})
  {:reply, {:ok, %{acked: true}}, socket}
end

# quests
def handle_in("action:quests", _payload, socket) do
  ZoneTicker.enqueue_action(socket.assigns.zone_id, socket.assigns.player_id,
    %{"action" => "quests"})
  {:reply, {:ok, %{acked: true}}, socket}
end

# look
def handle_in("action:look", _payload, socket) do
  ZoneTicker.enqueue_action(socket.assigns.zone_id, socket.assigns.player_id,
    %{"action" => "look"})
  {:reply, {:ok, %{acked: true}}, socket}
end

# enter
def handle_in("action:enter", %{"target" => exit_id}, socket) do
  ZoneTicker.enqueue_action(socket.assigns.zone_id, socket.assigns.player_id,
    %{"action" => "enter", "target" => exit_id})
  {:reply, {:ok, %{acked: true}}, socket}
end
```

**Step 2: Add action processing to `zone_ticker.ex` `apply_player_actions/4`**

Each action produces an `event` pushed back to the player via PubSub. Events are per-player, not broadcast to zone (dialogue is private).

```elixir
%{"action" => "look"} ->
  # Re-emit current state to player — handled in broadcast_tick, skip here
  {ents, acked}

%{"action" => "inventory"} ->
  player = find_player(ents, player_id)
  inventory = get_in(player.state, [:inventory]) || []
  send_player_event(zone_id, player_id, %{type: "inventory", items: inventory})
  {ents, acked}

%{"action" => "quests"} ->
  player = find_player(ents, player_id)
  quests = get_in(player.state, [:quests]) || []
  send_player_event(zone_id, player_id, %{type: "quests", quests: quests})
  {ents, acked}
```

**Step 3: Commit**
```bash
cd /home/hermes/agent_mmo
git add -A && git commit -m "feat: implement all action handlers in channel and ticker"
```

---

### Task 2: Scenario data format + loader

**Objective:** Hand-authored YAML scenario file loaded at startup, seeded into ETS.

**Files:**
- Create: `priv/scenarios/missing_merchant.yaml`
- Create: `lib/agent_mmo/world/scenario_loader.ex`

**Step 1: Create `priv/scenarios/missing_merchant.yaml`**

```yaml
id: missing_merchant
name: "The Missing Merchant"
start_zone: tavern_hall
player_spawn: {x: 3, y: 3}

zones:
  tavern_hall:
    width: 8
    height: 6
    tiles:
      # floor everywhere, walls on border (implicit)
    exits:
      - id: exit_north
        position: {x: 7, y: 4}
        label: "Dark Alley"
        destination_zone: dark_alley
        destination_position: {x: 0, y: 4}
    npcs:
      - id: npc_barkeep
        name: "Barkeep"
        position: {x: 1, y: 1}
        dialogue:
          greeting: "What can I get ya?"
          choices:
            - id: 1
              text: "Seen the merchant Aldric?"
              response: "Aye, headed north into the alley, looking scared."
              flags: [clue_north]
            - id: 2
              text: "What's north of here?"
              response: "Dark alley. Wouldn't go alone."
              flags: [clue_north]
            - id: 3
              text: "Nothing, thanks."
              response: "Safe travels."
      - id: npc_wench
        name: "Wench"
        position: {x: 3, y: 4}
        dialogue:
          greeting: "Evening."
          choices:
            - id: 1
              text: "Have you seen Aldric?"
              response: "The merchant? Ran past me heading north. Something chased him."
              flags: [clue_north]
            - id: 2
              text: "What's in the alley?"
              response: "Thugs and rats. Both dangerous, but one worse than the other."
              flags: [clue_thug]
            - id: 3
              text: "Never mind."
              response: "Suit yourself."

  dark_alley:
    width: 6
    height: 5
    exits:
      - id: exit_south
        position: {x: 0, y: 4}
        label: "Tavern Hall"
        destination_zone: tavern_hall
        destination_position: {x: 6, y: 4}
    enemies:
      - id: enemy_thug
        name: "Thug"
        position: {x: 1, y: 1}
        health: 30
        examine_text: "A dangerous-looking thug. This must be who scared the merchant."
        is_quest_target: true
      - id: enemy_rat
        name: "Rat"
        position: {x: 1, y: 3}
        health: 10
        examine_text: "A large rat. Unpleasant, but probably not responsible for the merchant's disappearance."
        penalty_on_kill: 20

quest:
  id: find_merchant
  name: "Find the Missing Merchant"
  description: "The merchant Aldric has gone missing. Find out what happened to him."
  objectives:
    - id: learn_direction
      description: "Learn where Aldric went"
      flags_required: [clue_north]
    - id: slay_thug
      description: "Deal with whatever threatened Aldric"
      flags_required: [killed_thug]
  completion_trigger:
    zone: tavern_hall
    flags_required: [killed_thug]
  scoring:
    base: 100
    per_step: -5
    rat_penalty: -20
    death_penalty: -10
    speed_bonus: {threshold_steps: 15, bonus: 20}
```

**Step 2: Create `lib/agent_mmo/world/scenario_loader.ex`**

```elixir
defmodule AgentMmo.World.ScenarioLoader do
  @moduledoc "Loads a YAML scenario file and seeds ETS tables for zones."

  def load!(scenario_id) do
    path = Application.app_dir(:agent_mmo, "priv/scenarios/#{scenario_id}.yaml")
    yaml = YamlElixir.read_from_file!(path)
    {:ok, yaml}
  end
end
```

**Step 3: Add `yaml_elixir` to `mix.exs` deps**
```elixir
{:yaml_elixir, "~> 2.9"}
```

**Step 4: `mix deps.get`**

**Step 5: Commit**
```bash
git add -A && git commit -m "feat: scenario YAML format and loader"
```

---

### Task 3: NPC GenServer with dialogue state

**Objective:** Each NPC is a GenServer loaded from scenario data. Tracks per-player dialogue state (which greeting/choice they're on).

**Files:**
- Create: `lib/agent_mmo/world/npc.ex`
- Modify: `lib/agent_mmo/world/zone_npc_sup.ex`

**Step 1: Create `lib/agent_mmo/world/npc.ex`**

```elixir
defmodule AgentMmo.World.NPC do
  use GenServer

  defstruct [:id, :name, :position, :zone_id, :dialogue, :dialogue_states]

  def start_link(opts) do
    npc_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_name(npc_id))
  end

  def speak(npc_id, player_id) do
    GenServer.call(via_name(npc_id), {:speak, player_id})
  end

  def reply(npc_id, player_id, choice_id) do
    GenServer.call(via_name(npc_id), {:reply, player_id, choice_id})
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      name: Keyword.fetch!(opts, :name),
      position: Keyword.fetch!(opts, :position),
      zone_id: Keyword.fetch!(opts, :zone_id),
      dialogue: Keyword.fetch!(opts, :dialogue),
      dialogue_states: %{}
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:speak, player_id}, _from, state) do
    choices = state.dialogue["choices"]
    response = %{
      type: "dialogue",
      npc: state.name,
      text: state.dialogue["greeting"],
      choices: Enum.map(choices, fn c -> %{id: c["id"], text: c["text"]} end)
    }
    {:reply, response, %{state | dialogue_states: Map.put(state.dialogue_states, player_id, :waiting_reply)}}
  end

  @impl true
  def handle_call({:reply, player_id, choice_id}, _from, state) do
    choice = Enum.find(state.dialogue["choices"], fn c -> c["id"] == choice_id end)
    if choice do
      flags = choice["flags"] || []
      response = %{
        type: "event",
        event: "npc_spoke",
        npc: state.name,
        text: choice["response"],
        flags: flags
      }
      {:reply, {:ok, response, flags}, %{state | dialogue_states: Map.delete(state.dialogue_states, player_id)}}
    else
      {:reply, {:error, "invalid choice"}, state}
    end
  end

  defp via_name(npc_id) do
    {:via, Registry, {AgentMmo.ZoneRegistry, {:npc, npc_id}}}
  end
end
```

**Step 2: Wire `speak` and `reply` through `zone_ticker.ex`**

In `apply_player_actions`, handle speak/reply by calling the NPC GenServer and emitting the response as a player event.

**Step 3: Commit**
```bash
git add -A && git commit -m "feat: NPC GenServer with per-player dialogue state"
```

---

### Task 4: Player state — inventory, quests, flags, score

**Objective:** Extend `PlayerSession` to track inventory, quest log, flags acquired, score, step count.

**Files:**
- Modify: `lib/agent_mmo/player/player_session.ex`

**Step 1: Extend player entity state**

```elixir
state: %{
  display_name: player_id,
  level: 1,
  animation: "idle",
  inventory: [],
  quests: ["Find the Missing Merchant"],
  flags: [],
  score: 100,
  steps: 0
}
```

**Step 2: Add `add_flag/2`, `deduct_score/2`, `increment_steps/1` calls wired through ZoneTicker**

**Step 3: Commit**
```bash
git add -A && git commit -m "feat: player state — inventory, quests, flags, score, steps"
```

---

### Task 5: Combat, flee, examine

**Objective:** Attack reduces enemy health. Enemy death triggers flag + score modifier. Flee moves player back one step. Examine returns entity description.

**Files:**
- Modify: `lib/agent_mmo/world/zone_ticker.ex`
- Modify: `lib/agent_mmo/world/entity.ex` (add `examine_text`, `penalty_on_kill`, `is_quest_target`)

**Step 1: Add fields to Entity**
```elixir
defstruct [
  :id, :kind, :position, :zone_id,
  :health, :max_health, :state, :updated_at,
  :examine_text, :is_quest_target, :penalty_on_kill
]
```

**Step 2: Add combat processing in zone_ticker**

```elixir
%{"action" => "attack", "target" => target_id} ->
  {new_ents, events} = resolve_attack(ents, player_id, target_id, zone_id)
  Enum.each(events, &send_player_event(zone_id, player_id, &1))
  {new_ents, acked}

%{"action" => "examine", "target" => target_id} ->
  target = Enum.find(ents, fn e -> e.id == target_id end)
  text = if target, do: target.examine_text || "You see nothing special.", else: "Not found."
  send_player_event(zone_id, player_id, %{type: "examine", text: text})
  {ents, acked}

%{"action" => "flee"} ->
  new_ents = move_player(ents, "player_#{player_id}", "south", zone_id)
  send_player_event(zone_id, player_id, %{type: "event", event: "fled"})
  {new_ents, acked}
```

**Step 3: Commit**
```bash
git add -A && git commit -m "feat: combat, flee, examine actions"
```

---

### Task 6: Zone transitions (enter action)

**Objective:** `enter` moves the player to a destination zone, updating their PlayerSession and ETS.

**Files:**
- Modify: `lib/agent_mmo/world/zone_ticker.ex`
- Modify: `lib/agent_mmo/player/player_session.ex`
- Modify: `lib/agent_mmo_web/channels/game_channel.ex`

**Step 1: Handle enter in zone_ticker**

```elixir
%{"action" => "enter", "target" => exit_id} ->
  exit = find_exit(zone_id, exit_id)
  if exit do
    send_player_event(zone_id, player_id, %{
      type: "zone_transition",
      destination_zone: exit.destination_zone,
      destination_position: exit.destination_position
    })
  end
  {ents, acked}
```

**Step 2: Handle `zone_transition` in GameChannel**

On receiving `zone_transition` event, the channel moves the player to the new zone — removes from current zone ETS, joins new zone ETS, resubscribes PubSub.

**Step 3: Commit**
```bash
git add -A && git commit -m "feat: zone transitions via enter action"
```

---

### Task 7: Quest completion + scoring

**Objective:** When completion trigger fires (correct zone + flags), mark quest complete, compute final score, broadcast `quest_complete`.

**Files:**
- Create: `lib/agent_mmo/world/quest_engine.ex`

**Step 1: Create `quest_engine.ex`**

```elixir
defmodule AgentMmo.World.QuestEngine do
  def check_completion(player_state, zone_id, scenario) do
    trigger = scenario["quest"]["completion_trigger"]
    required_flags = trigger["flags_required"]
    trigger_zone = trigger["zone"]

    has_flags = Enum.all?(required_flags, &(&1 in player_state.flags))
    in_zone = zone_id == trigger_zone

    if has_flags and in_zone do
      score = compute_score(player_state, scenario)
      {:complete, score}
    else
      :incomplete
    end
  end

  defp compute_score(player_state, scenario) do
    s = scenario["quest"]["scoring"]
    base = s["base"]
    step_penalty = player_state.steps * abs(s["per_step"])
    rat_penalty = if :killed_rat in player_state.flags, do: s["rat_penalty"], else: 0
    death_penalty = (player_state.deaths || 0) * abs(s["death_penalty"])
    speed_bonus =
      if player_state.steps <= s["speed_bonus"]["threshold_steps"],
        do: s["speed_bonus"]["bonus"], else: 0

    max(0, base - step_penalty + rat_penalty - death_penalty + speed_bonus)
  end
end
```

**Step 2: Call `QuestEngine.check_completion` on every zone transition**

**Step 3: Broadcast `quest_complete` event with score to player**

**Step 4: Commit**
```bash
git add -A && git commit -m "feat: quest completion detection and scoring"
```

---

### Task 8: API key auth + agent registration

**Objective:** Agents connect with a Bearer token. Server resolves to an agent identity. Leaderboard entries are keyed by agent identity.

**Files:**
- Create: `lib/agent_mmo/accounts/agent_key.ex`
- Modify: `lib/agent_mmo_web/channels/user_socket.ex`

**Step 1: Simple in-memory agent key store (ETS) for now**

```elixir
defmodule AgentMmo.Accounts.AgentKey do
  @table :agent_keys

  def init do
    :ets.new(@table, [:set, :public, :named_table])
  end

  def register(name) do
    key = "tb_" <> (:crypto.strong_rand_bytes(24) |> Base.encode16(case: :lower))
    :ets.insert(@table, {key, %{name: name, registered_at: DateTime.utc_now()}})
    key
  end

  def lookup(key) do
    case :ets.lookup(@table, key) do
      [{^key, agent}] -> {:ok, agent}
      [] -> :error
    end
  end
end
```

**Step 2: Authenticate in `UserSocket.connect/3`**

```elixir
def connect(%{"token" => token}, socket, _connect_info) do
  case AgentMmo.Accounts.AgentKey.lookup(token) do
    {:ok, agent} ->
      {:ok, assign(socket, :agent_name, agent.name)}
    :error ->
      :error
  end
end
```

**Step 3: Commit**
```bash
git add -A && git commit -m "feat: agent key auth in UserSocket"
```

---

### Task 9: Leaderboard (ETS, top 10)

**Objective:** On quest completion, upsert agent score into leaderboard ETS. Expose via HTTP endpoint.

**Files:**
- Create: `lib/agent_mmo/world/leaderboard.ex`
- Modify: `lib/agent_mmo_web/router.ex`
- Create: `lib/agent_mmo_web/controllers/leaderboard_controller.ex`

**Step 1: Create `leaderboard.ex`**

```elixir
defmodule AgentMmo.World.Leaderboard do
  @table :leaderboard

  def init do
    :ets.new(@table, [:ordered_set, :public, :named_table])
  end

  def submit(agent_name, quest_id, score) do
    key = {-score, agent_name, quest_id}
    :ets.insert(@table, {key, %{agent: agent_name, quest: quest_id, score: score, at: DateTime.utc_now()}})
  end

  def top(n \\ 10) do
    :ets.tab2list(@table)
    |> Enum.map(fn {_, v} -> v end)
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(n)
  end
end
```

**Step 2: Add GET /api/leaderboard route**

**Step 3: Commit**
```bash
git add -A && git commit -m "feat: leaderboard ETS store + HTTP endpoint"
```

---

### Task 10: Python SDK

**Objective:** Clean async Python SDK in `agent-mmo/clients/python/`. Agent code calls `move()`, `speak()`, `reply()`, etc. and awaits structured responses.

**Files:**
- Create: `agent-mmo/clients/python/tavernbench/__init__.py`
- Create: `agent-mmo/clients/python/tavernbench/client.py`
- Create: `agent-mmo/clients/python/pyproject.toml`

**Step 1: Create `client.py`**

```python
import asyncio
import json
import websockets

class TavernBenchClient:
    def __init__(self, url: str, token: str):
        self.url = url
        self.token = token
        self._ws = None
        self._state = {}
        self._event_queue = asyncio.Queue()

    async def connect(self, zone: str = "tavern_hall"):
        self._ws = await websockets.connect(
            f"{self.url}/socket/websocket?token={self.token}&vsn=2.0.0"
        )
        await self._join(zone)
        asyncio.create_task(self._recv_loop())

    async def _join(self, zone: str):
        msg = [None, None, f"zone:{zone}", "phx_join", {"protocol_version": "1.0"}]
        await self._ws.send(json.dumps(msg))

    async def _recv_loop(self):
        async for raw in self._ws:
            msg = json.loads(raw)
            await self._event_queue.put(msg)

    async def next_event(self, timeout: float = 10.0):
        return await asyncio.wait_for(self._event_queue.get(), timeout=timeout)

    async def _action(self, action: str, payload: dict = {}):
        msg = [None, None, f"zone:{self._state.get('zone', 'tavern_hall')}",
               f"action:{action}", payload]
        await self._ws.send(json.dumps(msg))

    # Action methods
    async def move(self, direction: str): await self._action("move", {"direction": direction})
    async def speak(self, target: str): await self._action("speak", {"target": target})
    async def reply(self, choice: int): await self._action("reply", {"choice": choice})
    async def examine(self, target: str): await self._action("examine", {"target": target})
    async def attack(self, target: str): await self._action("attack", {"target": target})
    async def flee(self): await self._action("flee")
    async def inventory(self): await self._action("inventory")
    async def quests(self): await self._action("quests")
    async def look(self): await self._action("look")
    async def enter(self, exit_id: str): await self._action("enter", {"target": exit_id})

    @property
    def state(self): return self._state
```

**Step 2: Create `pyproject.toml`**

```toml
[project]
name = "tavernbench"
version = "0.1.0"
description = "Python SDK for TavernBench — the agent benchmarking arena"
requires-python = ">=3.10"
dependencies = ["websockets>=16.0"]
```

**Step 3: Commit to public repo**
```bash
cd /home/hermes/agent-mmo
git add -A && git commit -m "feat: tavernbench Python SDK"
```

---

### Task 11: Go TUI spectator

**Objective:** Terminal UI that connects to the same WebSocket, renders the 2D map with entity positions, streams the action log, shows quest status and score.

**Files:**
- Create: `agent-mmo/clients/tui/main.go`
- Create: `agent-mmo/clients/tui/go.mod`

**Layout:**
```
┌─ TavernBench ──────────────────────────────────────────────┐
│ Zone: tavern_hall          Quest: Find the Missing Merchant │
├──────────────────┬─────────────────────────────────────────┤
│  . . . . . . . . │ [tick 14]                               │
│  . B . . . . . . │ Agent moved north                       │
│  . . . . . . . . │ Agent spoke to Barkeep                  │
│  . . . @ . . . . │ Barkeep: "Aye, headed north..."         │
│  . . . W . . . . │ Agent entered dark_alley                │
│  . . . . . . [↑] │ Agent attacked Thug                     │
├──────────────────┴─────────────────────────────────────────┤
│ HP: 100/100   Score: 75   Steps: 11   Flags: clue_north    │
└────────────────────────────────────────────────────────────┘
```

**Step 1: Create `go.mod`**
```
module tavernbench-tui

go 1.22

require (
    github.com/charmbracelet/bubbletea v0.26.6
    github.com/charmbracelet/lipgloss v0.12.1
    github.com/gorilla/websocket v1.5.3
)
```

**Step 2: Implement `main.go`** with Bubbletea model, WebSocket receiver goroutine, map renderer, action log panel, status bar.

**Step 3: Commit**
```bash
cd /home/hermes/agent-mmo
git add -A && git commit -m "feat: Go TUI spectator client"
```

---

### Task 12: End-to-end smoke test

**Objective:** Server running, agent connects via SDK, completes quest, TUI shows it live, leaderboard updated.

**Step 1: Start server**
```bash
cd /home/hermes/agent_mmo && mix phx.server
```

**Step 2: Register an agent key**
```bash
# In iex or via a mix task
AgentMmo.Accounts.AgentKey.register("hermes-test")
# Note the key: tb_...
```

**Step 3: Start TUI spectator**
```bash
cd agent-mmo/clients/tui
go run . --server ws://localhost:4000 --zone tavern_hall
```

**Step 4: Run agent**
```python
import asyncio
from tavernbench import TavernBenchClient

async def main():
    c = TavernBenchClient("ws://localhost:4000", token="tb_...")
    await c.connect()
    await c.look()
    # ... agent reasoning loop

asyncio.run(main())
```

**Step 5: Verify quest_complete event received with score > 0**

**Step 6: Verify leaderboard**
```bash
curl http://localhost:4000/api/leaderboard
```

---

## Post-demo checklist

- [ ] Deploy server to VPS at `tavernbench.dkta.dev` behind Caddy
- [ ] Create GitHub repos: `dsr-restyn/tavernbench-client` (public), keep server private
- [ ] Record demo video: TUI on left, agent reasoning log on right
- [ ] Write launch tweet thread on @dkta0
- [ ] Write blog post on blog.dkta.dev: "I built a dungeon crawler to benchmark AI agents"
