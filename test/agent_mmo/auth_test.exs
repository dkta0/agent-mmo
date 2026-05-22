defmodule AgentMmo.AuthTest do
  use AgentMmo.DataCase, async: false

  alias AgentMmo.Auth

  describe "issue_key/1" do
    test "creates a key with valid params" do
      assert {:ok, {plaintext, api_key}} =
               Auth.issue_key(%{"agent_name" => "test-agent", "owner" => "x@x.com"})

      assert String.starts_with?(plaintext, "tb_")
      # "tb_" (3) + 32 hex chars = 35
      assert String.length(plaintext) == 35
      assert api_key.agent_name == "test-agent"
      assert api_key.owner == "x@x.com"

      # Verify no plaintext in DB
      row = AgentMmo.Repo.get!(AgentMmo.ApiKey, api_key.id)
      refute row.key_hash == plaintext
      assert String.length(row.key_hash) == 64
    end

    test "returns error on short agent_name" do
      assert {:error, changeset} =
               Auth.issue_key(%{"agent_name" => "x", "owner" => "x@x.com"})

      assert changeset.errors[:agent_name]
    end

    test "returns error on missing fields" do
      assert {:error, changeset} = Auth.issue_key(%{})
      assert changeset.errors[:agent_name]
    end
  end

  describe "verify_key/1" do
    test "verifies a valid key" do
      {:ok, {plaintext, _}} =
        Auth.issue_key(%{"agent_name" => "verify-agent", "owner" => "v@v.com"})

      assert {:ok, api_key} = Auth.verify_key(plaintext)
      assert api_key.agent_name == "verify-agent"
    end

    test "returns :invalid for unknown key" do
      assert {:error, :invalid} =
               Auth.verify_key("tb_" <> String.duplicate("0", 32))
    end

    test "returns :invalid for non-string" do
      assert {:error, :invalid} = Auth.verify_key(nil)
    end
  end
end
