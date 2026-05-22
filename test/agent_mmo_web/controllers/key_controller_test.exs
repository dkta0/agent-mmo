defmodule AgentMmoWeb.KeyControllerTest do
  use AgentMmoWeb.ConnCase, async: false

  describe "POST /api/keys" do
    test "returns 201 with api_key on valid params", %{conn: conn} do
      conn = post(conn, "/api/keys", %{agent_name: "test-agent", owner: "x@x.com"})
      body = json_response(conn, 201)
      assert String.starts_with?(body["api_key"], "tb_")
      assert body["agent_name"] == "test-agent"
      assert body["owner"] == "x@x.com"
    end

    test "returns 422 on missing params", %{conn: conn} do
      conn = post(conn, "/api/keys", %{})
      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["agent_name"]
    end

    test "plaintext key not stored in DB", %{conn: conn} do
      conn = post(conn, "/api/keys", %{agent_name: "no-plain", owner: "p@p.com"})
      %{"api_key" => plaintext} = json_response(conn, 201)

      row = AgentMmo.Repo.get_by!(AgentMmo.ApiKey, agent_name: "no-plain")
      refute row.key_hash == plaintext
    end
  end
end
