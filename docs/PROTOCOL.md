# TavernBench WebSocket Protocol — Frozen Contract v1.0

**Status:** FROZEN — breaking changes require a new major version  
**Version:** 1.0  
**Transport:** Phoenix Channels over WebSocket  
**Encoding:** JSON (UTF-8)  
**Tick rate:** 500 ms server-side (`:tick_interval_ms` config key)  
**RFC 2119 keywords apply throughout:** MUST, MUST NOT, SHOULD, MAY.

This document is the machine-authoritative contract. Both the **auth PR** (server-side key
validation + socket auth middleware) and the **Python SDK** MUST be validated against every
section marked with a compliance tag before merge. See Section 10 for the compliance checklist.

> Narrative rationale and design decisions live in `protocol.md`.  
> This document is prescriptive, not explanatory.

---

## 1. Wire Format

Every frame on the WebSocket connection is a 5-element JSON array:

```
[join_ref, ref, topic, event, payload]
```

| Pos | Field      | Type            | Rule |
|-----|------------|-----------------|------|
| 0   | join_ref   | string \| null  | MUST be the same string sent in the `phx_join` for that channel; null for all other frames |
| 1   | ref        | string \| null  | Client MUST use a monotonically-incrementing integer string ("1", "2", …); server echos the same ref in `phx_reply`; null for unsolicited server pushes |
| 2   | topic      | string          | MUST match a topic pattern from Section 2 |
| 3   | event      | string          | One of the event names defined in this document |
| 4   | payload    | object          | MUST be a JSON object (not null, not array) |

Deviations from this shape MUST be rejected by the server with a WebSocket close code 1003.

---

## 2. Topic Naming

| Pattern           | Channel         | Clients         |
|-------------------|-----------------|-----------------|
| `zone:<zone_id>`  | GameChannel     | Python SDK (player) |
| `spectate:<zone_id>` | SpectateChannel | Go TUI (read-only) |

`zone_id` MUST be a non-empty snake_case string (regex: `[a-z][a-z0-9_]*`).

---

## 3. Authentication

### 3.1 Connection — Query Parameters

The WebSocket upgrade request MUST include:

| Parameter        | Required | Type   | Rule |
|------------------|----------|--------|------|
| `api_key`        | yes      | string | 64-char hex string (32 bytes, SHA-256-hashed, see ADR-002) |
| `protocol_version` | yes    | string | MUST equal `"1.0"` |

The server MUST validate `api_key` before upgrading. On failure: close with HTTP 403 before the upgrade completes.

```
ws://<host>/socket/websocket?api_key=<64-hex-chars>&protocol_version=1.0
```

### 3.2 Channel Join — phx_join Payload

```json
["<join_ref>", "<ref>", "zone:<zone_id>", "phx_join", {
  "protocol_version": "1.0"
}]
```

`protocol_version` in the join payload MUST match the value sent at connect time.

**Success reply:**

```json
["<join_ref>", "<ref>", "zone:<zone_id>", "phx_reply", {
  "status": "ok",
  "response": {
    "status": "ok",
    "protocol_version": "1.0"
  }
}]
```

**Error — wrong version:**

```json
["<join_ref>", "<ref>", "zone:<zone_id>", "phx_reply", {
  "status": "error",
  "response": {
    "reason": "unsupported_protocol_version",
    "supported": "1.0"
  }
}]
```

**Error — missing version:**

```json
["<join_ref>", "<ref>", "zone:<zone_id>", "phx_reply", {
  "status": "error",
  "response": {
    "reason": "missing_protocol_version"
  }
}]
```

---

## 4. Client → Server: Action Messages

### 4.1 General Ack Shape

Every action MUST receive a synchronous `phx_reply` before the next tick delivers the outcome.

**Accepted:**
```json
[null, "<ref>", "zone:<zone_id>", "phx_reply", {
  "status": "ok",
  "response": {"acked": true}
}]
```

**Rejected (validation failure):**
```json
[null, "<ref>", "zone:<zone_id>", "phx_reply", {
  "status": "error",
  "response": {"code": "<ERROR_CODE>"}
}]
```

The `code` field MUST be one of the codes in Section 7.

### 4.2 Action Definitions

All actions use event name `action:<name>`.

#### action:move

```typescript
// Payload type
{
  direction: "north" | "south" | "east" | "west"
            | "northeast" | "northwest" | "southeast" | "southwest",  // REQUIRED
  seq?: integer  // optional; server echoes acked values in tick.acked_seqs
}
```

Sync error codes: `MISSING_DIRECTION`, `INVALID_DIRECTION`

#### action:enter

```typescript
{ target: string }  // exit entity ID — REQUIRED
```

Sync error codes: `MISSING_TARGET`

#### action:speak

```typescript
{ target: string }  // NPC entity ID — REQUIRED
```

Sync error codes: `MISSING_TARGET`

#### action:reply

```typescript
{ choice: integer }  // choice ID from preceding dialogue.choices — REQUIRED
```

Sync error codes: `MISSING_CHOICE`

#### action:examine

```typescript
{ target: string }  // entity ID — REQUIRED
```

Sync error codes: `MISSING_TARGET`

#### action:pickup

```typescript
{ target: string }  // item entity ID — REQUIRED
```

Sync error codes: `MISSING_TARGET`

#### action:drop

```typescript
{ item: string }  // item ID from inventory — REQUIRED
```

Sync error codes: `MISSING_ITEM`

#### action:use

```typescript
{
  item: string,    // item ID from inventory — REQUIRED
  target?: string  // entity ID to apply to; omit for self-use
}
```

Sync error codes: `MISSING_ITEM`

#### action:attack

```typescript
{ target: string }  // entity ID — REQUIRED
```

Sync error codes: `MISSING_TARGET`

#### action:flee

```typescript
{}  // empty payload
```

#### action:inventory

```typescript
{}  // empty payload
```

#### action:quests

```typescript
{}  // empty payload
```

#### action:look

```typescript
{}  // empty payload
```

#### action:wait

```typescript
{}  // empty payload
```

---

## 5. Server → Client: Push Messages

All server pushes MUST have `join_ref = null` and `ref = null` unless they are `phx_reply` frames.

### 5.1 tick

**Event name:** `tick`  
**Broadcast:** all connected players and spectators in the zone  
**Frequency:** every 500 ms

```typescript
// TickPayload
{
  tick:          integer,    // monotonically increasing server counter
  timestamp_ms:  integer,    // Unix epoch milliseconds
  zone_id:       string,     // current zone identifier
  zone: {
    id:     string,
    width:  integer,
    height: integer
  },
  position:   {x: integer, y: integer},  // receiving player's position
  entities:   Entity[],    // visible entities (see 5.1.1)
  inventory:  InventoryItem[],
  quest_log:  Quest[],
  score:      integer,     // current run score
  steps:      integer,     // steps taken this run
  events:     any[],       // deprecated; SHOULD be empty; MAY carry legacy entries
  acked_seqs: integer[]    // seq values from action:move processed this tick
}
```

#### 5.1.1 Entity

```typescript
{
  type:        "player" | "npc" | "enemy" | "item" | "exit",
  id:          string,
  name:        string,
  position:    {x: integer, y: integer},
  distance:    float,      // Euclidean distance from receiving player
  health?:     integer,    // ONLY for type == "enemy"
  max_health?: integer     // ONLY for type == "enemy"
}
```

`health` and `max_health` MUST be omitted for non-enemy entities. Clients MUST NOT rely on
their presence for non-enemies.

#### 5.1.2 InventoryItem

```typescript
{
  id:       string,
  name:     string,
  quantity: integer  // >= 1
}
```

#### 5.1.3 Quest

```typescript
{
  id:          string,
  name:        string,
  description: string,
  objectives: {
    id:          string,
    description: string,
    complete:    boolean
  }[],
  complete: boolean
}
```

### 5.2 event

**Event name:** `event`  
**Direction:** server → player (private, not broadcast)

Common envelope:

```typescript
{
  type: string,  // one of the subtypes below
  ...            // subtype-specific fields
}
```

#### 5.2.1 npc_spoke

```typescript
{ type: "npc_spoke", npc: string, text: string }
```

Triggered by: `action:reply`

#### 5.2.2 examine

```typescript
{ type: "examine", target_id: string, text: string }
```

Triggered by: `action:examine`

#### 5.2.3 combat

```typescript
{
  type:             "combat",
  attacker:         string,  // "player" or entity ID
  target:           string,  // entity ID
  damage:           integer,
  target_health:    integer,
  target_max_health: integer,
  target_alive:     boolean
}
```

Triggered by: `action:attack`  
Also broadcast to spectators.

#### 5.2.4 entity_died

```typescript
{
  type:        "entity_died",
  entity_id:   string,
  entity_name: string,
  score_delta: integer  // negative if a penalty applies
}
```

Also broadcast to spectators.

#### 5.2.5 player_died

```typescript
{
  type:             "player_died",
  score_delta:      integer,  // negative penalty
  respawn_zone:     string,
  respawn_position: {x: integer, y: integer}
}
```

Private to the dying player.

#### 5.2.6 fled

```typescript
{ type: "fled" }
```

Triggered by: successful `action:flee`  
Also broadcast to spectators.

#### 5.2.7 inventory

```typescript
{
  type:  "inventory",
  items: InventoryItem[]
}
```

Triggered by: `action:inventory`

#### 5.2.8 quests

```typescript
{
  type:   "quests",
  quests: Quest[]
}
```

Triggered by: `action:quests`

#### 5.2.9 zone_entered

```typescript
{
  type:      "zone_entered",
  from_zone: string,
  to_zone:   string,
  position:  {x: integer, y: integer}
}
```

Triggered by: successful `action:enter`  
After receiving this event the client MUST `phx_leave` the current topic and `phx_join` the new zone topic before sending any further actions.

#### 5.2.10 item_picked_up

```typescript
{
  type:      "item_picked_up",
  item_id:   string,
  item_name: string
}
```

Triggered by: successful `action:pickup`

#### 5.2.11 item_dropped

```typescript
{
  type:     "item_dropped",
  item_id:  string,
  position: {x: integer, y: integer}
}
```

Triggered by: successful `action:drop`

### 5.3 dialogue

**Event name:** `dialogue`  
**Direction:** server → player (private)

```typescript
{
  npc_id:  string,
  npc:     string,
  text:    string,
  choices: {id: integer, text: string}[]
}
```

Triggered by: `action:speak`  
After `action:reply`, the server delivers an `event` of type `npc_spoke`.

### 5.4 quest_complete

**Event name:** `quest_complete`  
**Direction:** broadcast to zone and spectators

```typescript
{
  quest_id:    string,
  quest_name:  string,
  final_score: integer,
  steps_taken: integer,
  breakdown: {
    base:          integer,
    step_penalty:  integer,  // <= 0
    speed_bonus:   integer,  // >= 0
    rat_penalty:   integer,  // <= 0
    death_penalty: integer   // <= 0
  }
}
```

### 5.5 error

**Event name:** `error`  
**Direction:** server → player (private)

```typescript
{
  code:        string,   // machine-readable; one of Section 7
  message:     string,   // human-readable
  action_ref?: string    // ref from the offending client message, when available
}
```

---

## 6. Spectator Channel

Spectators connect on `spectate:<zone_id>`. The join payload is identical to a player join (Section 3.2).

Spectator tick payload is the same shape as Section 5.1 with these differences:
- `position` field MUST be omitted (no per-player perspective)
- `inventory`, `quest_log`, `score`, `steps` MUST be omitted or empty

Spectator push visibility:

| Push event             | Spectator receives? |
|------------------------|---------------------|
| `tick`                 | yes                 |
| `event` — combat       | yes                 |
| `event` — entity_died  | yes                 |
| `event` — fled         | yes                 |
| `quest_complete`       | yes                 |
| `dialogue`             | no                  |
| `event` — npc_spoke    | no                  |
| `event` — examine      | no                  |
| `event` — inventory    | no                  |
| `event` — quests       | no                  |
| `error`                | no                  |

Spectators MUST NOT send `action:*` messages. The server MUST reply with error code
`SPECTATOR_ACTION_FORBIDDEN` and ignore the message.

---

## 7. Error Codes

All codes are uppercase_snake unless marked with an asterisk (legacy lowercase kept for backward
compat).

| Code | When raised |
|------|-------------|
| `INVALID_DIRECTION` | `action:move` direction not in allowed set |
| `MISSING_DIRECTION` | `action:move` with no direction field |
| `MISSING_TARGET` | `action:speak`, `action:examine`, `action:attack`, `action:enter`, `action:pickup` — target field absent |
| `MISSING_CHOICE` | `action:reply` — choice field absent |
| `MISSING_ITEM` | `action:drop`, `action:use` — item field absent |
| `TARGET_NOT_FOUND` | Target entity ID does not exist in the zone |
| `NOT_IN_DIALOGUE` | `action:reply` sent without an open dialogue |
| `INVALID_CHOICE` | Choice ID not in the current dialogue's choices array |
| `EXIT_NOT_FOUND` | `action:enter` target is not a valid exit entity |
| `NOT_ADJACENT` | Action requires adjacency (enter, pickup) but player is too far |
| `ITEM_NOT_IN_INVENTORY` | `action:drop` or `action:use` item not in player inventory |
| `TARGET_ALREADY_DEAD` | `action:attack` on an entity with 0 HP |
| `SPECTATOR_ACTION_FORBIDDEN` | Any `action:*` from a spectator socket |
| `unsupported_protocol_version`* | Join payload `protocol_version` not in server's supported set |
| `missing_protocol_version`* | Join payload missing `protocol_version` |

---

## 8. Keep-Alive

Heartbeat on the reserved `phoenix` topic every ≤ 30 seconds:

```json
[null, "hb-<n>", "phoenix", "heartbeat", {}]
```

Server reply:
```json
[null, "hb-<n>", "phoenix", "phx_reply", {"status": "ok", "response": {}}]
```

The server MUST close the connection with code 1000 if no heartbeat is received within 60 seconds.

---

## 9. Session Lifecycle

```
Client                                    Server
  |                                          |
  |-- WS GET /socket/websocket?api_key=... ->|  (HTTP 403 if key invalid)
  |<-- 101 Switching Protocols --------------|
  |                                          |
  |-- phx_join zone:tavern_hall ------------>|
  |<-- phx_reply {status: ok} --------------|
  |                                          |
  | [every 500 ms]                           |
  |<-- tick {tick: N, entities: [...]} ------|
  |                                          |
  |-- action:speak {target: npc_barkeep} --->|
  |<-- phx_reply {acked: true} -------------|
  |<-- dialogue {npc: "Barkeep", ...} -------|
  |                                          |
  |-- action:reply {choice: 1} ------------>|
  |<-- phx_reply {acked: true} -------------|
  |<-- event {type: "npc_spoke", ...} -------|
  |                                          |
  |-- action:enter {target: exit_north} ---->|
  |<-- phx_reply {acked: true} -------------|
  |<-- event {type: "zone_entered", ...} ----|
  |-- phx_leave zone:tavern_hall ----------->|
  |-- phx_join zone:dark_alley ------------->|
  |<-- phx_reply {status: ok} --------------|
  |                                          |
  |  [combat loop …]                         |
  |                                          |
  |<-- quest_complete {final_score: 85} -----|
```

---

## 10. Versioning

The server declares the protocol version in the join reply (`protocol_version: "1.0"`).  
Clients that send an unsupported version MUST receive `unsupported_protocol_version` and the join MUST fail.

Breaking changes (removed fields, renamed events, changed types) MUST increment the major version.  
Non-breaking additions (new optional fields, new event subtypes) MUST NOT increment the version.  
The server MAY support multiple major versions via parallel socket routes (e.g. `/socket/v2/websocket`).

---

## 11. Implementation Compliance Checklist

Use this section as a merge gate. Both the auth PR and the SDK PR MUST address every item
before merge is approved.

### Auth PR Checklist

- [ ] WebSocket upgrade handler reads `api_key` query parameter
- [ ] Key is looked up from the `api_keys` table via constant-time SHA-256 comparison (see ADR-002)
- [ ] HTTP 403 returned before upgrade if key is missing or invalid (no Phoenix socket opened)
- [ ] `protocol_version` query parameter read and stored on socket assigns
- [ ] `phx_join` handler checks `payload["protocol_version"]` against server's supported list
- [ ] Returns `unsupported_protocol_version` error shape (Section 3.2) on version mismatch
- [ ] Returns `missing_protocol_version` error shape (Section 3.2) on absent version
- [ ] `player_id` derived from socket ID, not from join payload
- [ ] `SPECTATOR_ACTION_FORBIDDEN` emitted for action:* on SpectateChannel

### Python SDK Checklist

- [ ] Connects with `?api_key=<key>&protocol_version=1.0` query string (Section 3.1)
- [ ] Sends `phx_join` with `{"protocol_version": "1.0"}` payload (Section 3.2)
- [ ] Handles `phx_reply` with `status: "error"` on join (surfaces `reason` to caller)
- [ ] All 14 action senders produce the exact payload shapes from Section 4.2
- [ ] `action:move` includes optional `seq` field and SDK tracks acked_seqs from tick
- [ ] Parses `tick` payload into a typed object matching TickPayload (Section 5.1)
- [ ] `entities` items with `type == "enemy"` expose `health` / `max_health`; others do not
- [ ] Dispatches `dialogue` event to a registered handler (Section 5.3)
- [ ] Dispatches all `event` subtypes (Sections 5.2.1–5.2.11) to handlers
- [ ] On `zone_entered`: leaves current topic, joins new topic before next action
- [ ] Sends Phoenix heartbeat on `phoenix` topic every ≤ 30 s (Section 8)
- [ ] `ref` counter is monotonically increasing integer serialized as string
- [ ] `join_ref` is non-null only on `phx_join` frames for that channel
