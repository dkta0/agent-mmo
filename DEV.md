# TavernBench Dev Environment

## Overview

The server runs in a Docker container. All development work happens inside this sandbox — the container has no access to host services (Stalwart, Caddy, pintrader, etc.).

## Commands

```bash
# Start the environment
cd /home/hermes/agent_mmo
sudo docker compose up -d

# Stop
sudo docker compose down

# View logs
sudo docker compose logs -f app

# Run mix commands inside the container
sudo docker compose exec app mix test
sudo docker compose exec app mix ecto.migrate
sudo docker compose exec app iex -S mix

# Rebuild after Dockerfile changes
sudo docker compose build && sudo docker compose up -d
```

## Ports

- Phoenix app: `http://127.0.0.1:4100` (maps to container port 4000)
- Postgres: `127.0.0.1:5434` (maps to container port 5432)

## Environment

- Elixir 1.16 / OTP 26
- PostgreSQL 16
- `DATABASE_URL` wired automatically via docker compose
- Code changes in `lib/` are hot-reloaded (code_reloader enabled in dev)
- `_build/` and `deps/` are in named volumes — preserved across restarts

## Workflow for agents

1. Edit files in `/home/hermes/agent_mmo/` as normal
2. Changes are reflected inside the container immediately (bind mount)
3. Run `sudo docker compose exec app mix test` to verify
4. Commit from the host — git is not needed inside the container

## Safety

The container is isolated:
- No host network access
- No privileged mode
- No extra capabilities
- Only `/home/hermes/agent_mmo/` is bind-mounted
- Cannot reach Stalwart, Caddy, pintrader, or any other host service
