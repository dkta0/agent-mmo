defmodule AgentMmo.AccountsTest do
  use AgentMmo.DataCase, async: true

  alias AgentMmo.Accounts
  alias AgentMmo.Accounts.User

  describe "register_user/1" do
    test "creates user with valid email and password" do
      assert {:ok, %User{} = user} =
               Accounts.register_user(%{email: "new@example.com", password: "supersecret"})

      assert user.email == "new@example.com"
      assert user.hashed_password != nil
      assert user.hashed_password != "supersecret"
    end

    test "rejects duplicate email" do
      Accounts.register_user(%{email: "dup@example.com", password: "supersecret"})

      assert {:error, changeset} =
               Accounts.register_user(%{email: "dup@example.com", password: "othersecret"})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "rejects password shorter than 8 chars" do
      assert {:error, changeset} =
               Accounts.register_user(%{email: "short@example.com", password: "abc"})

      assert errors_on(changeset).password != []
    end

    test "rejects invalid email format" do
      assert {:error, changeset} =
               Accounts.register_user(%{email: "not-an-email", password: "supersecret"})

      assert errors_on(changeset).email != []
    end
  end

  describe "get_user_by_email_and_password/2" do
    setup do
      {:ok, user} =
        Accounts.register_user(%{email: "auth@example.com", password: "correcthorse"})

      %{user: user}
    end

    test "returns user on correct credentials", %{user: user} do
      found = Accounts.get_user_by_email_and_password("auth@example.com", "correcthorse")
      assert found.id == user.id
    end

    test "returns nil on wrong password" do
      assert nil == Accounts.get_user_by_email_and_password("auth@example.com", "wrongpassword")
    end

    test "returns nil on unknown email" do
      assert nil == Accounts.get_user_by_email_and_password("nobody@example.com", "correcthorse")
    end
  end

  describe "session tokens" do
    setup do
      {:ok, user} =
        Accounts.register_user(%{email: "session@example.com", password: "supersecret"})

      %{user: user}
    end

    test "create, fetch, and delete a session token", %{user: user} do
      token = Accounts.create_session_token(user)
      assert is_binary(token)

      fetched = Accounts.get_user_by_session_token(token)
      assert fetched.id == user.id

      Accounts.delete_session_token(token)
      assert nil == Accounts.get_user_by_session_token(token)
    end
  end
end
