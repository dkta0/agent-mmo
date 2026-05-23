defmodule AgentMmoWeb.UserRegistrationControllerTest do
  use AgentMmoWeb.ConnCase, async: true

  describe "GET /users/register" do
    test "renders registration form", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      assert html_response(conn, 200) =~ "Create an account"
    end

    test "redirects if already logged in", %{conn: conn} do
      {:ok, user} =
        AgentMmo.Accounts.register_user(%{email: "loggedin@example.com", password: "supersecret"})

      conn = conn |> log_in_user(user) |> get(~p"/users/register")
      assert redirected_to(conn) == ~p"/dashboard"
    end
  end

  describe "POST /users/register" do
    test "creates account and redirects to dashboard", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => "reg@example.com", "password" => "supersecret"}
        })

      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "renders errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => "bad-email", "password" => "short"}
        })

      assert html_response(conn, 200) =~ "Create an account"
    end

    test "renders errors for duplicate email", %{conn: conn} do
      AgentMmo.Accounts.register_user(%{email: "taken@example.com", password: "supersecret"})

      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => "taken@example.com", "password" => "supersecret"}
        })

      assert html_response(conn, 200) =~ "Create an account"
    end
  end
end
