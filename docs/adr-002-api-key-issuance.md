# ADR-002: API Key Issuance Strategy

## Status
Proposed

## Context

TavernBench authenticates WebSocket connections by checking `api_key` against a
hardcoded list in `config.exs`. Scores are held in process state and lost on
restart. The landing page promises account creation, key generation, and a live
leaderboard — none of which exist. We need the simplest persistent solution that
works for machine-to-machine (agent) consumers: no browser redirect, no OAuth
dance.

Constraints:
- Consumers are AI agents, not human browsers. Keys must be usable in a single
  HTTP request or a WebSocket connect parameter.
- Postgres is already present (phoenix_ecto, postgrex in mix.exs).
- No existing user model — this is greenfield.
- Production is a separate container; migrations must be safe to run there
  without downtime.

## Decision

Store API keys in Postgres. Issue them via a simple POST endpoint. No external
auth service.

Specifically:
- `api_keys` table: stores a PBKDF2/bcrypt hash of the key, plus agent metadata.
- On issuance, return the plaintext key once. Never store it in plaintext.
- On every WebSocket connect, hash the incoming key and compare to the DB row.
  Cache the lookup in ETS for the duration of the connection (one DB hit per
  connect, not per message).
- Key namespacing: each key is bound to an (agent_name, owner_email) pair.
  The leaderboard groups by agent_name.

Key format: `tb_<32 random hex bytes>` — readable prefix aids debugging,
sufficient entropy (128 bits) against brute force.

## Tradeoffs

Accepted:
- Key rotation requires a new POST and disposing of the old key. No built-in
  revocation TTL. Acceptable for a benchmarking tool where keys aren't
  payment-sensitive.
- Hashing on every connect adds ~1ms per WebSocket handshake. Mitigated by ETS
  cache keyed on the plaintext key with a short TTL (60 s) or until the socket
  closes.
- No rate-limiting on key issuance endpoint in v1. A coder task should add it
  later.

Not accepted:
- Storing plaintext keys. Even in a dev tool this creates unnecessary exposure
  if the DB is dumped.

## Rejected Alternatives

**Auth0 / external IdP**
- Requires browser redirect or device-flow OAuth. AI agents cannot do that.
  Machine credentials (client_credentials grant) are possible but add an
  external dependency, latency, and cost. Rejected: complexity >> benefit.

**JWT tokens signed by the server**
- Stateless, no DB hit on verify. But we need server-side revocation and
  per-key quota/usage tracking. A stateless token makes that hard without a
  denylist table — at which point you have the same DB hit anyway. Rejected:
  no meaningful gain over hashed DB keys.

**Keep hardcoded list, just make it an env var**
- Zero-effort but doesn't enable self-service key creation for agents, and
  provides no leaderboard linkage. Rejected: doesn't meet product requirements.

## Key Derivation

Use `:crypto.hash(:sha256, key)` for speed on lookups (bcrypt is too slow to
run on every WebSocket handshake even with caching, and SHA-256 of a 128-bit
random key is not a password-guessing target). Store the hex digest.

If the threat model ever escalates to adversarial key theft from the DB, swap
to Argon2 with a stored salt — the column is already there.
