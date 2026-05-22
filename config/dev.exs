import Config

# Use DATABASE_URL if set (Docker), fallback to local dev defaults
if database_url = System.get_env("DATABASE_URL") do
  config :agent_mmo, AgentMmo.Repo,
    url: database_url,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10
else
  config :agent_mmo, AgentMmo.Repo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    database: "agent_mmo_dev",
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10
end

config :agent_mmo, AgentMmoWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: System.get_env("SECRET_KEY_BASE") || "JxIfvQfYXbjP8jjtQf130J+dwhFP8iYNHftUJCocdetvw6AKOMTcQ1I7Ei3AaE24",
  watchers: []

config :agent_mmo, dev_routes: true

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
