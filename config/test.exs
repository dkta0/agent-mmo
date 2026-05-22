import Config

# Configure your database
if database_url = System.get_env("DATABASE_URL") do
  config :agent_mmo, AgentMmo.Repo,
    url: database_url,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
else
  config :agent_mmo, AgentMmo.Repo,
    username: "agent_mmo",
    password: "tavernbench_dev",
    hostname: System.get_env("PGHOST", "postgres"),
    database: "agent_mmo_test#{System.get_env("MIX_TEST_PARTITION")}",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :agent_mmo, AgentMmoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "2VqSObcpOah2c/h+u3LNpY9yOdp6R/MoHVn7YMYnuPYaj1++NsNUbtHknwJajFnB",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
