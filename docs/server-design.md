# TavernBench Server Design

> Interface contracts, module names, struct fields, function signatures, and GenServer message types.
> No implementation code. This document is the handoff to the `coder` profile.

---

## Module Map

```
lib/agent_mmo/
  world/
    entity.ex            -- Entity struct + to_json/1 (EXISTS — needs extension)
    zone_supervisor.ex   -- ZoneSupervisor: ETS owner, join/leave (EXISTS — needs exit seeding)
    zone_ticker.ex       -- ZoneTicker GenServer, 500ms tick (EXISTS — needs all actions added)
    zone_npc_sup.ex      -- ZoneNPCSup: DynamicSupervisor for NPC children (EXISTS)
    npc.ex               -- NPC GenServer, per-player dialogue state (NEW)
    scenario_loader.ex   -- ScenarioLoader: YAML → ETS seed (NEW)
  player/
    player_supervisor.ex -- PlayerSupervisor: DynamicSupervisor (EXISTS)
    player_session.ex    -- PlayerSession GenServer, player-scoped mutable state (EXISTS — needs extension)
  quest/
    quest_engine.ex      -- QuestEngine: objective tracking, scoring, completion (NEW)
  auth/
    api_key.ex           -- ApiKey: key format, hashing, Ecto schema (NEW)
    auth_plug.ex         -- AuthPlug: Plug behaviour, lookup, reject middleware (NEW)
lib/agent_mmo_web/
  channels/
    game_channel.ex      -- GameChannel: Phoenix.Channel, all 14 actions (EXISTS — needs extension)
  router.ex              -- pipeline :api_key_protected (needs auth_plug wired)
```

---

## 1. Entity Model — `AgentMmo.World.Entity`

Extends the existing struct. Fields added for combat, examine text, scoring hooks.

```elixir
@enforce_keys [:id, :kind, :position, :zone_id]
defstruct [
  # existing
  :id,           # String.t()  — "player_<id>", "npc_barkeep", "enemy_thug", "item_key"
  :kind,         # :player | :npc | :enemy | :item | :exit
  :position,     # {x :: non_neg_integer(), y :: non_neg_integer()}
  :zone_id,      # String.t()
  :health,       # integer() | nil   — nil for non-combatants (NPCs, items, exits)
  :max_health,   # integer() | nil
  :state,        # map()  — kind-specific extra fields (see per-kind tables below)
  :updated_at,   # integer()  — tick number of last mutation

  # new fields
  :name,           # String.t()  — display name ("Barkeep", "Thug", "Gold Key")
  :examine_text,   # String.t() | nil  — returned by :examine action
  :is_quest_target,  # boolean()  — true on enemy_thug
  :penalty_on_kill,  # integer() | nil  — deducted from score when killed (rat: 20)
  :dialogue_id,    # String.t() | nil  — foreign key into NPC GenServer registry for :npc kind
  :exit_to,        # %{zone_id: String.t(), position: {x, y}} | nil  — for :exit kind
  :exit_label      # String.t() | nil  — "Dark Alley"
]

@type kind :: :player | :npc | :enemy | :item | :exit

@type t :: %__MODULE__{
  id: String.t(),
  kind: kind(),
  position: {non_neg_integer(), non_neg_integer()},
  zone_id: String.t(),
  health: integer() | nil,
  max_health: integer() | nil,
  state: map(),
  updated_at: integer(),
  name: String.t() | nil,
  examine_text: String.t() | nil,
  is_quest_target: boolean(),
  penalty_on_kill: integer() | nil,
  dialogue_id: String.t() | nil,
  exit_to: %{zone_id: String.t(), position: {integer(), integer()}} | nil,
  exit_label: String.t() | nil
}
```

### Per-kind `state` map shape

| kind   | state keys |
|--------|-----------|
| :player | `%{display_name, level, animation, inventory, quests, flags, score, steps}` |
| :npc   | `%{display_name, animation}` (live state in NPC GenServer, not ETS) |
| :enemy | `%{animation}` |
| :item  | `%{item_type, quantity}` |
| :exit  | `%{}` |

---

## 2. Zone GenServer — `AgentMmo.World.ZoneTicker`

Existing GenServer. Only the tick callback and action dispatch need extending.

### Struct

```elixir
defstruct [
  :zone_id,           # String.t()
  :tick,              # non_neg_integer()
  :action_queues,     # %{player_id => [action_map]}
  :tick_interval_ms,  # pos_integer()  — default 500
  :zone_meta          # %{width, height, exits}  — loaded from scenario at init
]
```

### Client API

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
def start_link(opts)

@spec enqueue_action(zone_id :: String.t(), player_id :: String.t(), action :: map()) :: :ok
def enqueue_action(zone_id, player_id, action)
```

### GenServer messages (cast)

```
{:enqueue_action, player_id :: String.t(), action :: action_map()}
```

### GenServer messages (info)

```
:tick    -- internal, scheduled via Process.send_after/3
```

### Zone meta seeded into ETS (`:zone_meta` key)

```elixir
%{
  zone_id: String.t(),
  width: pos_integer(),
  height: pos_integer(),
  exits: [%{id: String.t(), position: {x, y}, label: String.t(),
             destination_zone: String.t(), destination_position: {x, y}}]
}
```

### Tick broadcast payload (PubSub `"zone:<id>"`)

```elixir
%{
  tick: non_neg_integer(),
  timestamp_ms: integer(),
  zone_id: String.t(),
  entities: [entity_json],       # Entity.to_json/1 for all entities in zone
  events: [event_map],           # zone-wide events (enemy died, etc.)
  acked_seqs: [integer()]
}
```

### Per-player event payload (PubSub `"player:<player_id>"`)

All non-broadcast responses go here. GameChannel subscribes to this topic on join.

```elixir
# dialogue response
%{type: "dialogue", npc: String.t(), text: String.t(),
  choices: [%{id: integer(), text: String.t()}]}

# NPC reply result
%{type: "event", event: "npc_spoke", npc: String.t(), text: String.t(), flags: [String.t()]}

# examine result
%{type: "examine", text: String.t()}

# inventory result
%{type: "inventory", items: [item_json]}

# quests result
%{type: "quests", quests: [quest_status_json]}

# zone transition (sent before player moves zones)
%{type: "zone_change", zone_id: String.t(), position: %{x: integer(), y: integer()}}

# combat result
%{type: "combat", attacker: String.t(), target: String.t(),
  damage: integer(), target_health: integer(), killed: boolean()}

# score update
%{type: "score_update", score: integer(), delta: integer(), reason: String.t()}

# quest completion
%{type: "quest_complete", quest_id: String.t(), score: integer(), steps: integer()}

# death / respawn
%{type: "death", message: String.t()}

# error
%{type: "error", code: String.t(), message: String.t()}
```

---

## 3. NPC GenServer — `AgentMmo.World.NPC`

One process per NPC instance per zone. Registered via `AgentMmo.ZoneRegistry`.

### Struct

```elixir
defstruct [
  :id,              # String.t()  — "npc_barkeep"
  :name,            # String.t()  — "Barkeep"
  :position,        # {x, y}
  :zone_id,         # String.t()
  :dialogue,        # dialogue_spec()  — loaded from scenario YAML
  :dialogue_states  # %{player_id => :idle | :waiting_reply}
]

@type dialogue_spec :: %{
  greeting: String.t(),
  choices: [%{id: integer(), text: String.t(), response: String.t(), flags: [String.t()]}]
}
```

### Client API

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
def start_link(opts)

@spec speak(npc_id :: String.t(), player_id :: String.t()) ::
  {:ok, dialogue_response()} | {:error, String.t()}
def speak(npc_id, player_id)

@spec reply(npc_id :: String.t(), player_id :: String.t(), choice_id :: integer()) ::
  {:ok, npc_reply_response(), flags :: [String.t()]} | {:error, String.t()}
def reply(npc_id, player_id, choice_id)
```

### GenServer messages (call)

```
{:speak, player_id :: String.t()}
  -> {:ok, dialogue_response()} | {:error, String.t()}

{:reply, player_id :: String.t(), choice_id :: integer()}
  -> {:ok, npc_reply_response(), [String.t()]} | {:error, String.t()}
```

### Registry key

```
{:npc, npc_id :: String.t()}  -- in AgentMmo.ZoneRegistry
```

---

## 4. Player State — `AgentMmo.Player.PlayerSession`

Tracks per-session mutable state. ETS holds the Entity (position, health). PlayerSession holds meta-state (score, flags, inventory, quests).

### Struct

```elixir
defstruct [
  :player_id,        # String.t()
  :account_id,       # String.t() | nil  — set after auth
  :current_zone_id,  # String.t()
  :socket_pid,       # pid() | nil

  # new fields
  :inventory,        # [item_ref()]  — list of item entity ids
  :quests,           # [quest_status()]
  :flags,            # [String.t()]  — acquired knowledge/event flags
  :score,            # integer()  — starts at 100, modified by scoring rules
  :steps             # non_neg_integer()
]

@type item_ref :: String.t()

@type quest_status :: %{
  quest_id: String.t(),
  name: String.t(),
  objectives: [%{id: String.t(), description: String.t(), completed: boolean()}],
  completed: boolean()
}
```

### Client API

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
def start_link(opts)

@spec get_state(player_id :: String.t()) :: {:ok, t()} | {:error, :not_found}
def get_state(player_id)

@spec add_flag(player_id :: String.t(), flag :: String.t()) :: :ok
def add_flag(player_id, flag)

@spec add_item(player_id :: String.t(), item_id :: String.t()) :: :ok
def add_item(player_id, item_id)

@spec remove_item(player_id :: String.t(), item_id :: String.t()) :: :ok | {:error, :not_found}
def remove_item(player_id, item_id)

@spec deduct_score(player_id :: String.t(), amount :: integer(), reason :: String.t()) :: integer()
def deduct_score(player_id, amount, reason)  # returns new score

@spec increment_steps(player_id :: String.t()) :: non_neg_integer()
def increment_steps(player_id)  # returns new step count

@spec update_zone(player_id :: String.t(), zone_id :: String.t()) :: :ok
def update_zone(player_id, zone_id)

@spec complete_quest(player_id :: String.t(), quest_id :: String.t()) :: :ok
def complete_quest(player_id, quest_id)
```

### GenServer messages (call)

```
:get_state
  -> {:ok, t()}

{:add_flag, flag :: String.t()}
  -> :ok

{:add_item, item_id :: String.t()}
  -> :ok

{:remove_item, item_id :: String.t()}
  -> :ok | {:error, :not_found}

{:deduct_score, amount :: integer(), reason :: String.t()}
  -> new_score :: integer()

:increment_steps
  -> steps :: non_neg_integer()

{:update_zone, zone_id :: String.t()}
  -> :ok

{:complete_quest, quest_id :: String.t()}
  -> :ok
```

### Registry key

```
{:player_session, player_id :: String.t()}  -- in AgentMmo.ZoneRegistry
```

---

## 5. Action Dispatcher — `AgentMmoWeb.GameChannel` + `AgentMmo.World.ZoneTicker`

The dispatcher is split: GameChannel validates and enqueues; ZoneTicker processes on tick.

### All 14 actions — wire shapes (client → server)

| action      | topic              | payload fields                      | requires target? |
|-------------|--------------------|-------------------------------------|-----------------|
| move        | action:move        | `{direction, seq?}`                 | no |
| enter       | action:enter       | `{target: exit_id}`                 | yes (exit entity id) |
| speak       | action:speak       | `{target: npc_id}`                  | yes (npc entity id) |
| reply       | action:reply       | `{choice: integer()}`               | no (stateful) |
| examine     | action:examine     | `{target: entity_id}`               | yes |
| pickup      | action:pickup      | `{target: item_id}`                 | yes |
| drop        | action:drop        | `{target: item_id}`                 | yes |
| use         | action:use         | `{target: item_id, on?: entity_id?}`| yes |
| attack      | action:attack      | `{target: enemy_id}`                | yes |
| flee        | action:flee        | `{}`                                | no |
| inventory   | action:inventory   | `{}`                                | no |
| quests      | action:quests      | `{}`                                | no |
| look        | action:look        | `{}`                                | no |
| wait        | action:wait        | `{}`                                | no |

### Action result routing

- **Broadcast** (all players in zone see it): move, enter, attack (death), drop
- **Per-player only** (via `"player:<id>"` PubSub): speak, reply, examine, pickup, inventory, quests, look, wait, flee, score_update, zone_change

### Action processing logic (ZoneTicker, no implementation — intent only)

| action    | mutates ETS?       | calls external process? | emits event type |
|-----------|--------------------|------------------------|-----------------|
| move      | yes (position)     | no                     | tick broadcast |
| enter     | yes (zone_id, position) | PlayerSession.update_zone | zone_change (per-player) |
| speak     | no                 | NPC.speak/2            | dialogue |
| reply     | no                 | NPC.reply/3 + PlayerSession.add_flag | event:npc_spoke |
| examine   | no                 | no                     | examine |
| pickup    | yes (remove item)  | PlayerSession.add_item | tick broadcast |
| drop      | yes (add item)     | PlayerSession.remove_item | tick broadcast |
| use       | conditional        | no                     | event:used |
| attack    | yes (health, dead) | PlayerSession.deduct_score (penalty_on_kill or death) | combat, score_update |
| flee      | yes (position back) | PlayerSession.deduct_score | event:fled |
| inventory | no                 | PlayerSession.get_state | inventory |
| quests    | no                 | PlayerSession.get_state | quests |
| look      | no                 | no                     | (next tick already broadcasts) |
| wait      | no                 | no                     | (no-op) |

---

## 6. Quest System — `AgentMmo.Quest.QuestEngine`

Stateless module called by ZoneTicker when flag or zone changes occur.
Quest data is loaded from scenario YAML at startup (stored in ETS or application env).

### Quest spec shape (from ScenarioLoader)

```elixir
@type objective :: %{
  id: String.t(),
  description: String.t(),
  flags_required: [String.t()]
}

@type completion_trigger :: %{
  zone: String.t(),            # player must be in this zone
  flags_required: [String.t()] # player must have all these flags
}

@type scoring_config :: %{
  base: integer(),
  per_step: integer(),          # negative — applied at completion
  rat_penalty: integer(),       # negative — applied on :penalty_on_kill entity kill
  death_penalty: integer(),     # negative — applied on player death + respawn
  speed_bonus: %{threshold_steps: integer(), bonus: integer()} | nil
}

@type quest_spec :: %{
  id: String.t(),
  name: String.t(),
  description: String.t(),
  objectives: [objective()],
  completion_trigger: completion_trigger(),
  scoring: scoring_config()
}
```

### Client API

```elixir
@spec check_objectives(quest_spec(), player_flags :: [String.t()]) ::
  [%{id: String.t(), completed: boolean()}]
def check_objectives(quest_spec, player_flags)

@spec check_completion(quest_spec(), player_flags :: [String.t()], current_zone :: String.t()) ::
  boolean()
def check_completion(quest_spec, player_flags, current_zone)

@spec compute_score(quest_spec(), steps :: non_neg_integer(), penalty_events :: [score_event()]) ::
  integer()
def compute_score(quest_spec, steps, penalty_events)
```

### Score event type

```elixir
@type score_event :: {:rat_killed} | {:player_died} | {:custom, integer(), String.t()}
```

### Design notes

- QuestEngine is a pure-function module, not a GenServer. No process required.
- ZoneTicker calls `QuestEngine.check_completion/3` after every action that could satisfy a trigger (zone change, flag acquisition).
- When check_completion returns true, ZoneTicker sends a `quest_complete` event to the player and calls `PlayerSession.complete_quest/2`.
- Final score = `QuestEngine.compute_score/3` called at completion time.

---

## 7. API Key Auth

### Key format

```
tvb_<32 random hex bytes>
example: tvb_a3f1e2d4c5b6a7f8e9d0c1b2a3f4e5d6c7b8a9f0e1d2c3b4a5f6e7d8c9b0
```

- Prefix `tvb_` identifies TavernBench keys (distinguishes from env vars / other tokens).
- 32 bytes = 64 hex chars. Entropy: 256 bits. Brute-force infeasible.
- Hash stored: `:crypto.hash(:sha256, raw_key)` |> Base.encode16(case: :lower)

### Schema — `AgentMmo.Auth.ApiKey`

```elixir
# Ecto schema (SQLite via Repo)
schema "api_keys" do
  field :key_hash,    :string   # sha256 hex of raw key — indexed, unique
  field :label,       :string   # human label ("hermes-agent-1")
  field :owner_id,    :string   # opaque agent/user id
  field :active,      :boolean, default: true
  field :last_used_at, :utc_datetime_usec
  timestamps()
end

@type t :: %__MODULE__{
  id: integer(),
  key_hash: String.t(),
  label: String.t(),
  owner_id: String.t(),
  active: boolean(),
  last_used_at: DateTime.t() | nil,
  inserted_at: DateTime.t(),
  updated_at: DateTime.t()
}
```

### Client API — `AgentMmo.Auth.ApiKey`

```elixir
@spec generate() :: {raw_key :: String.t(), key_hash :: String.t()}
def generate()
# Returns {raw_key, hash}. Caller persists hash. raw_key shown once to user.

@spec hash(raw_key :: String.t()) :: String.t()
def hash(raw_key)

@spec lookup(raw_key :: String.t()) :: {:ok, t()} | {:error, :invalid | :inactive}
def lookup(raw_key)
# Hashes input, queries DB, checks active flag, touches last_used_at.
```

### Plug — `AgentMmo.Auth.AuthPlug`

```elixir
@behaviour Plug

@spec init(opts :: keyword()) :: keyword()
def init(opts)
# opts: [realm: "TavernBench"] — used in WWW-Authenticate header

@spec call(conn :: Plug.Conn.t(), opts :: keyword()) :: Plug.Conn.t()
def call(conn, opts)
# Reads Authorization: Bearer <key> header.
# On success: assigns conn.assigns[:api_key] = %ApiKey{}, continues pipeline.
# On failure: halts, returns 401 JSON {error: "unauthorized"}.
```

### Router wiring

```elixir
pipeline :api_key_protected do
  plug AgentMmo.Auth.AuthPlug
end

scope "/api", AgentMmoWeb do
  pipe_through [:api, :api_key_protected]
  # future REST endpoints
end
```

WebSocket join (`UserSocket.connect/3`) also validates the key:

```elixir
@spec connect(params :: map(), socket :: Socket.t(), connect_info :: map()) ::
  {:ok, Socket.t()} | :error
def connect(%{"api_key" => key}, socket, _connect_info)
# Calls ApiKey.lookup/1. On success assigns :owner_id to socket. On failure :error.
```

---

## Dependency Graph

```
ScenarioLoader
  └─ seeds → ZoneSupervisor (ETS: zone_meta, entities, exits)
              └─ spawns → ZoneTicker
                           └─ calls → NPC (speak/reply)
                           └─ calls → QuestEngine (pure)
                           └─ calls → PlayerSession (flags, score, steps, zone)
                           └─ broadcasts → PubSub zone:*
                           └─ sends → PubSub player:*

GameChannel
  ├─ authenticates via → UserSocket.connect (ApiKey.lookup)
  ├─ dispatches to → ZoneTicker.enqueue_action
  └─ subscribes → PubSub zone:* + player:*

AuthPlug (REST pipeline only)
  └─ calls → ApiKey.lookup
```

No circular dependencies. QuestEngine is a leaf (pure module, no dependencies on GenServers).

---

## Open Decisions for Coder

1. **Respawn position** — when a player dies, where do they respawn? Plan says -10 score; does position reset to spawn point? Assume yes (start_zone, player_spawn from scenario). Coder should confirm with spec owner.

2. **Concurrent dialogue** — if a player initiates speak with NPC A and then speak with NPC B before replying, what happens? Proposed: NPC A state remains :waiting_reply indefinitely. A second speak to a different NPC is allowed (resets nothing in NPC A). The reply action targets the last NPC spoken to — GameChannel should track `last_npc_id` in socket assigns.

3. **pickup/drop/use** — scenario has no items in v1. Coder should implement the channel handlers and ticker stubs but can return `{:error, "no items in zone"}` until scenario items are added.

4. **ApiKey storage** — plan uses SQLite. No migration toolchain is set up yet. Coder should add Ecto migration for `api_keys` table.
