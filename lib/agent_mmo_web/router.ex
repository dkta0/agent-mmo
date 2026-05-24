defmodule AgentMmoWeb.Router do
  use AgentMmoWeb, :router

  import AgentMmoWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AgentMmoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  ## Auth routes (public)
  scope "/", AgentMmoWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
  end

  scope "/", AgentMmoWeb do
    pipe_through :browser

    delete "/users/log_out", UserSessionController, :delete
    get "/", PageController, :home
  end

  ## Protected routes
  scope "/dashboard", AgentMmoWeb do
    pipe_through [:browser, :require_authenticated_user]

    live "/", DashboardLive, :index
    live "/keys/new", DashboardLive, :new_key
    live "/keys/:id", DashboardLive, :show_key
  end

  ## API (JSON)
  scope "/", AgentMmoWeb do
    pipe_through :api
    get "/health", HealthController, :index
  end

  ## Embeddable spectator widget (HTML, not :api pipeline)
  scope "/", AgentMmoWeb do
    get "/spectate", SpectateController, :embed
  end

  scope "/api", AgentMmoWeb do
    pipe_through :api
    get "/leaderboard", LeaderboardController, :index
    get "/scenarios", ScenarioController, :index
    get "/spectate/current", SpectateController, :current
    get "/spectate/ranked", SpectateController, :ranked
    post "/keys", KeyController, :create
    post "/runs", RunController, :create
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:agent_mmo, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: AgentMmoWeb.Telemetry
    end
  end
end
