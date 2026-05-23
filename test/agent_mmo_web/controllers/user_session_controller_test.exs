defmodule AgentMmoWeb.UserSessionControllerTest do
  use AgentMmoWeb.ConnCase, async: true

  setup do
    {:ok, user} =
      AgentMmo.Accounts.register_user(%{email: "session@example.com", password: "supersecret"})

    %{user: user}
  end

  describe "GET /users/log_in" do
    test "renders login form", %{conn: conn} do
      conn = get(conn, ~p"/users/log_in")
      assert html_response(conn, 200) =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> get(~p"/users/log_in")
      assert redirected_to(conn) == ~p"/dashboard"
    end
  end

  describe "POST /users/log_in" do
    test "logs in with correct credentials and redirects to dashboard", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => "session@example.com", "password" => "supersecret"}
        })

      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "renders error on invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => "session@example.com", "password" => "wrongpassword"}
        })

      assert html_response(conn, 200) =~ "Invalid email or password"
    end
  end

  describe "DELETE /users/log_out" do
    test "logs out authenticated user", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end
  end
end
