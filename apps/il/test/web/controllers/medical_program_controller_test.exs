defmodule Il.Web.MedicalProgramControllerTest do
  @moduledoc false

  use Il.Web.ConnCase

  describe "list medical programs" do
    test "search by id", %{conn: conn} do
      %{id: id} = insert(:prm, :medical_program)
      insert(:prm, :medical_program)
      conn = get conn, medical_program_path(conn, :index), %{"id" => id}
      resp = json_response(conn, 200)["data"]
      assert 1 == length(resp)
      assert id == Map.get(hd(resp), "id")

      assert_medical_program_list(resp)
    end

    test "search by name", %{conn: conn} do
      insert(:prm, :medical_program, name: "test")
      insert(:prm, :medical_program, name: "other")
      conn = get conn, medical_program_path(conn, :index), %{"name" => "te"}
      resp = json_response(conn, 200)["data"]
      assert 1 == length(resp)
      assert "test" == Map.get(hd(resp), "name")
    end

    test "search by is_active", %{conn: conn} do
      %{id: id} = insert(:prm, :medical_program, is_active: true)
      insert(:prm, :medical_program, is_active: false)
      conn = get conn, medical_program_path(conn, :index), %{"is_active" => true}
      resp = json_response(conn, 200)["data"]
      assert 1 == length(resp)
      assert id == Map.get(hd(resp), "id")
      assert Map.get(hd(resp), "is_active")
    end

    test "search by all possible options", %{conn: conn} do
      %{id: id} = insert(:prm, :medical_program, name: "some name", is_active: true)
      insert(:prm, :medical_program, is_active: false)
      conn = get conn, medical_program_path(conn, :index), %{"is_active" => true, "name" => "some"}
      resp = json_response(conn, 200)
      data = resp["data"]
      assert 1 == length(data)
      assert id == Map.get(hd(data), "id")
      assert Map.get(hd(data), "is_active")
      assert "some name" == Map.get(hd(data), "name")

      schema =
        "test/data/medical_program/list_medical_programs_response_schema.json"
        |> File.read!()
        |> Poison.decode!()

      assert :ok = NExJsonSchema.Validator.validate(schema, resp)
    end
  end

  describe "create medical program" do
    test "invalid name", %{conn: conn} do
      conn = post conn, medical_program_path(conn, :create)
      resp = json_response(conn, 422)
      assert %{"error" => %{"invalid" => [%{"entry" => "$.name"}]}} = resp
    end

    test "success create medical program", %{conn: conn} do
      conn = post conn, medical_program_path(conn, :create), name: "test"
      resp = json_response(conn, 201)

      schema =
        "test/data/medical_program/create_medical_program_response_schema.json"
        |> File.read!()
        |> Poison.decode!()

      assert :ok = NExJsonSchema.Validator.validate(schema, resp["data"])
    end
  end

  describe "get by id" do
    test "success", %{conn: conn} do
      %{id: id} = insert(:prm, :medical_program)
      conn = get conn, medical_program_path(conn, :show, id)
      resp = json_response(conn, 200)["data"]
      assert id == resp["id"]

      schema =
        "test/data/medical_program/get_medical_program_response_schema.json"
        |> File.read!()
        |> Poison.decode!()

      assert :ok = NExJsonSchema.Validator.validate(schema, resp)
    end

    test "fail", %{conn: conn} do
      conn = put_client_id_header(conn)
      assert_raise Ecto.NoResultsError, fn ->
        get conn, medical_program_path(conn, :show, Ecto.UUID.generate())
      end
    end
  end

  describe "deactivate" do
    test "success", %{conn: conn} do
      %{id: id} = medical_program = insert(:prm, :medical_program)
      conn = patch conn, medical_program_path(conn, :deactivate, medical_program)

      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      refute json_response(conn, 200)["data"]["is_active"]
    end

    test "medical program is inactive", %{conn: conn} do
      medical_program = insert(:prm, :medical_program, is_active: false)

      conn = patch conn, medical_program_path(conn, :deactivate, medical_program)
      refute json_response(conn, 200)["data"]["is_active"]
    end

    test "medical program has active program medications", %{conn: conn} do
      medical_program = insert(:prm, :medical_program)
      insert(:prm, :program_medication, medical_program_id: medical_program.id)

      conn = patch conn, medical_program_path(conn, :deactivate, medical_program)
      err_msg = "This program has active participants. Only medical programs without participants can be deactivated"
      assert err_msg == json_response(conn, 409)["error"]["message"]
    end
  end

  defp assert_medical_program_list(response) do
    schema =
      "specs/json_schemas/medical_program/medical_program_get_list_response.json"
      |> File.read!()
      |> Poison.decode!()

    assert :ok == NExJsonSchema.Validator.validate(schema, response)
  end
end
