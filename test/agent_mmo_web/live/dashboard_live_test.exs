defmodule AgentMmoWeb.DashboardLiveTest do
  use AgentMmoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentMmo.Accounts

  defp register_and_log_in(conn) do
    {:ok, user} = Accounts.register_user(%{email: "dash#{System.unique_integer()}@test.com", password: "supersecret"})
    conn = log_in_user(conn, user)
    {conn, user}
  end

  describe "authentication" do
    test "redirects unauthenticated users to login", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, "/dashboard")
      assert path =~ "/users/log_in"
    end
  end

  describe "dashboard mount" do
    test "shows dashboard when logged in", %{conn: conn} do
      {conn, user} = register_and_log_in(conn)
      {:ok, lv, html} = live(conn, "/dashboard")
      assert html =~ "Dashboard"
      assert html =~ user.email
      assert html =~ "API Keys"
      assert html =~ "Quick Start"
      assert html =~ "Recent Runs"
    end

    test "shows empty state when no keys", %{conn: conn} do
      {conn, _user} = register_and_log_in(conn)
      {:ok, _lv, html} = live(conn, "/dashboard")
      assert html =~ "No active API keys"
    end

    test "shows empty state when no runs", %{conn: conn} do
      {conn, _user} = register_and_log_in(conn)
      {:ok, _lv, html} = live(conn, "/dashboard")
      assert html =~ "No runs yet"
    end
  end

  describe "key form" do
    test "shows key form on button click", %{conn: conn} do
      {conn, _user} = register_and_log_in(conn)
      {:ok, lv, _html} = live(conn, "/dashboard")
      html = lv |> element("button", "+ Generate Key") |> render_click()
      assert html =~ "Agent name"
    end

    test "hides form on cancel", %{conn: conn} do
      {conn, _user} = register_and_log_in(conn)
      {:ok, lv, _html} = live(conn, "/dashboard")
      lv |> element("button", "+ Generate Key") |> render_click()
      html = lv |> element("button", "Cancel") |> render_click()
      refute html =~ ~r/name="agent_name"/
    end
  end

  describe "generate key" do
    test "generates key and shows it once", %{conn: conn} do
      {conn, _user} = register_and_log_in(conn)
      {:ok, lv, _html} = live(conn, "/dashboard")
      lv |> element("button", "+ Generate Key") |> render_click()

      html =
        lv
        |> form("form[phx-submit=generate_key]", %{agent_name: "test-agent"})
        |> render_submit()

      assert html =~ "New API key generated"
      assert html =~ "tb_"
      assert html =~ "test-agent"
    end

    test "can dismiss the generated key", %{conn: conn} do
      {conn, _user} = register_and_log_in(conn)
      {:ok, lv, _html} = live(conn, "/dashboard")
      lv |> element("button", "+ Generate Key") |> render_click()
      lv |> form("form[phx-submit=generate_key]", %{agent_name: "dismiss-test"}) |> render_submit()

      html = lv |> element("button", "I've saved it, dismiss") |> render_click()
      refute html =~ "New API key generated"
    end

    test "shows error for blank agent_name", %{conn: conn} do
      {conn, _user} = register_and_log_in(conn)
      {:ok, lv, _html} = live(conn, "/dashboard")
      lv |> element("button", "+ Generate Key") |> render_click()
      html = lv |> form("form[phx-submit=generate_key]", %{agent_name: "  "}) |> render_submit()
      assert html =~ "blank"
    end
  end

  describe "revoke key" do
    test "can revoke a key", %{conn: conn} do
      {conn, user} = register_and_log_in(conn)
      {:ok, {_plaintext, _api_key}} =
        AgentMmo.Auth.issue_key(%{
          "agent_name" => "my-agent",
          "owner" => user.email,
          "user_id" => user.id
        })

      {:ok, lv, html} = live(conn, "/dashboard")
      assert html =~ "my-agent"

      html = lv |> element("button", "Revoke") |> render_click()
      refute html =~ "my-agent"
    end
  end

  describe "integration tabs" do
    test "default tab is claude-code", %{conn: conn} do
      {conn, _user} = register_and_log_in(conn)
      {:ok, _lv, html} = live(conn, "/dashboard")
      assert html =~ "~/.claude/mcp.json"
    end

    test "switching to cursor tab shows cursor content", %{conn: conn} do
      {conn, _user} = register_and_log_in(conn)
      {:ok, lv, _html} = live(conn, "/dashboard")
      html = lv |> element("button[phx-value-tab=cursor]") |> render_click()
      assert html =~ "~/.cursor/mcp.json"
    end

    test "switching to codex tab shows codex content", %{conn: conn} do
      {conn, _user} = register_and_log_in(conn)
      {:ok, lv, _html} = live(conn, "/dashboard")
      html = lv |> element("button[phx-value-tab=codex]") |> render_click()
      assert html =~ "~/.codex/config.json"
    end

    test "switching to roll-your-own shows python snippet", %{conn: conn} do
      {conn, _user} = register_and_log_in(conn)
      {:ok, lv, _html} = live(conn, "/dashboard")
      html = lv |> element("button[phx-value-tab=diy]") |> render_click()
      assert html =~ "TavernBenchClient"
    end
  end
end
