# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

# Seed a predictable dev key so existing clients still work
dev_key = "dev-key"
key_hash = :crypto.hash(:sha256, dev_key) |> Base.encode16(case: :lower)
key_prefix = String.slice(dev_key, 0, 5)

unless AgentMmo.Repo.get_by(AgentMmo.ApiKey, key_hash: key_hash) do
  AgentMmo.Repo.insert!(%AgentMmo.ApiKey{
    key_hash: key_hash,
    key_prefix: key_prefix,
    agent_name: "dev-agent",
    owner: "dev@localhost"
  })
  IO.puts("Dev key 'dev-key' seeded.")
else
  IO.puts("Dev key already exists, skipping.")
end
