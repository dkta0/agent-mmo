defmodule AgentMmoWeb.Router do
  use AgentMmoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AgentMmoWeb do
    pipe_through :browser
    get "/", PageController, :home
    get "/signup", PageController, :signup
  end

  scope "/", AgentMmoWeb do
    pipe_through :api
    get "/health", HealthController, :index
  end

  scope "/api", AgentMmoWeb do
    pipe_through :api
    get "/leaderboard", LeaderboardController, :index
    post "/keys", KeyController, :create
  end

  if Application.compile_env(:agent_mmo, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: AgentMmoWeb.Telemetry
    end
  end
end
