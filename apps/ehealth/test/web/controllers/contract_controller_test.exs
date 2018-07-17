defmodule EHealth.Web.ContractControllerTest do
  @moduledoc false

  use EHealth.Web.ConnCase

  import EHealth.Expectations.Signature
  import Mox
  alias EHealth.Contracts.Contract
  alias EHealth.Divisions.Division
  alias Ecto.UUID
  import Mox

  describe "show contract" do
    test "finds contract successfully and nhs can see any contracts", %{conn: conn} do
      nhs(2)

      expect(MediaStorageMock, :create_signed_url, 6, fn _, _, id, resource_name, _ ->
        {:ok, %{"data" => %{"secret_url" => "http://url.com/#{id}/#{resource_name}"}}}
      end)

      contract_request = insert(:il, :contract_request, status: "SIGNED")
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)

      assert response =
               %{"data" => response_data} =
               conn
               |> put_client_id_header(UUID.generate())
               |> get(contract_path(conn, :show, contract.id))
               |> json_response(200)

      assert response_data["id"] == contract.id
      assert length(response["urgent"]["documents"]) == 3

      Enum.each(response["urgent"]["documents"], fn urgent_data ->
        assert Map.has_key?(urgent_data, "type")
        assert(Map.has_key?(urgent_data, "url"))
      end)
    end

    test "ensure TOKENS_TYPES_PERSONAL has access to own contracts", %{conn: conn} do
      expect(MediaStorageMock, :create_signed_url, 4, fn _, _, id, resource_name, _ ->
        {:ok, %{"data" => %{"secret_url" => "http://url.com/#{id}/#{resource_name}"}}}
      end)

      msp()
      contractor_legal_entity = insert(:prm, :legal_entity)
      contract_request = insert(:il, :contract_request)

      contract =
        insert(
          :prm,
          :contract,
          contractor_legal_entity_id: contractor_legal_entity.id,
          contract_request_id: contract_request.id
        )

      assert %{"data" => response_data} =
               conn
               |> put_client_id_header(contractor_legal_entity.id)
               |> get(contract_path(conn, :show, contract.id))
               |> json_response(200)

      assert response_data["contractor_legal_entity"]["id"] == contractor_legal_entity.id
    end

    test "ensure TOKENS_TYPES_PERSONAL has no access to other contracts", %{conn: conn} do
      msp()
      contractor_legal_entity = insert(:prm, :legal_entity)
      contract = insert(:prm, :contract)

      assert %{"error" => %{"type" => "forbidden", "message" => _}} =
               conn
               |> put_client_id_header(contractor_legal_entity.id)
               |> get(contract_path(conn, :show, contract.id))
               |> json_response(403)
    end

    test "not found", %{conn: conn} do
      nhs()

      assert %{"error" => %{"type" => "not_found"}} =
               conn
               |> put_client_id_header(UUID.generate())
               |> get(contract_path(conn, :show, UUID.generate()))
               |> json_response(404)
    end
  end

  describe "contract list" do
    test "validating search params: ignore invalid search params", %{conn: conn} do
      nhs()
      insert(:prm, :contract)
      insert(:prm, :contract)

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_path(conn, :index), %{created_by: UUID.generate()})

      assert resp = json_response(conn, 200)["data"]
      assert length(resp) == 2
    end

    test "validating search params: edrpou is defined, contractor_legal_entity_id is not defined", %{conn: conn} do
      nhs()
      edrpou = "5432345432"
      contractor_legal_entity = insert(:prm, :legal_entity, edrpou: edrpou)
      insert(:prm, :contract, contractor_legal_entity_id: contractor_legal_entity.id)
      insert(:prm, :contract)

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_path(conn, :index), %{edrpou: edrpou})

      assert resp = json_response(conn, 200)["data"]
      assert length(resp) == 1
      assert resp |> hd() |> Map.get("contractor_legal_entity_id") == contractor_legal_entity.id
    end

    test "validating search params: edrpou is not defined, contractor_legal_entity_id is defined", %{conn: conn} do
      nhs()
      contractor_legal_entity = insert(:prm, :legal_entity)
      insert(:prm, :contract, contractor_legal_entity_id: contractor_legal_entity.id)
      insert(:prm, :contract)

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_path(conn, :index), %{contractor_legal_entity_id: contractor_legal_entity.id})

      assert resp = json_response(conn, 200)["data"]
      assert length(resp) == 1
      assert resp |> hd() |> Map.get("contractor_legal_entity_id") == contractor_legal_entity.id
    end

    test "validating search params: edrpou and contractor_legal_entity_id are defined and belong to the same legal entity",
         %{conn: conn} do
      nhs()
      edrpou = "5432345432"
      contractor_legal_entity = insert(:prm, :legal_entity, edrpou: edrpou)
      insert(:prm, :contract, contractor_legal_entity_id: contractor_legal_entity.id)
      insert(:prm, :contract)

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_path(conn, :index), %{edrpou: edrpou, contractor_legal_entity_id: contractor_legal_entity.id})

      assert resp = json_response(conn, 200)["data"]
      assert length(resp) == 1
      assert resp |> hd() |> Map.get("contractor_legal_entity_id") == contractor_legal_entity.id
    end

    test "validating search params: edrpou and contractor_legal_entity_id are defined and do not belong to the same legal entity",
         %{conn: conn} do
      nhs()
      edrpou = "5432345432"
      contractor_legal_entity = insert(:prm, :legal_entity)

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_path(conn, :index), %{edrpou: edrpou, contractor_legal_entity_id: contractor_legal_entity.id})

      resp = json_response(conn, 200)
      assert resp["data"] == []

      assert %{
               "page_number" => 1,
               "total_entries" => 0,
               "total_pages" => 1
             } = resp["paging"]
    end

    test "validating search params: page_size by default", %{conn: conn} do
      nhs()

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_path(conn, :index))

      resp = json_response(conn, 200)

      assert %{
               "page_size" => 50,
               "page_number" => 1,
               "total_entries" => 0,
               "total_pages" => 1
             } = resp["paging"]
    end

    test "validating search params: page_size defined by user", %{conn: conn} do
      nhs()
      page_size = 100

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_path(conn, :index), %{page_size: page_size})

      resp = json_response(conn, 200)

      assert %{
               "page_size" => ^page_size,
               "page_number" => 1,
               "total_entries" => 0,
               "total_pages" => 1
             } = resp["paging"]
    end

    test "success contract list for NHS admin user", %{conn: conn} do
      nhs()
      contract = insert(:prm, :contract, is_suspended: true)
      insert(:prm, :contract)

      params = %{
        id: contract.id,
        contractor_owner_id: contract.contractor_owner_id,
        nhs_signer_id: contract.nhs_signer_id,
        status: contract.status,
        is_suspended: true,
        date_from_start_date: contract.start_date,
        date_to_start_date: contract.start_date,
        date_from_end_date: contract.end_date,
        date_to_end_date: contract.end_date,
        contract_number: contract.contract_number
      }

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_path(conn, :index), params)

      assert resp = json_response(conn, 200)["data"]
      assert length(resp) == 1
    end

    test "success contract list for NHS admin user from dates only", %{conn: conn} do
      nhs()
      contract = insert(:prm, :contract)
      insert(:prm, :contract, start_date: ~D[2017-01-01])

      params = %{
        date_from_start_date: contract.start_date,
        date_from_end_date: contract.end_date
      }

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_path(conn, :index), params)

      assert resp = json_response(conn, 200)["data"]
      assert length(resp) == 1
    end

    test "success contract list for NHS admin user to dates only", %{conn: conn} do
      nhs()
      contract = insert(:prm, :contract, end_date: ~D[2017-01-01])
      insert(:prm, :contract)

      params = %{
        date_to_start_date: contract.start_date,
        date_to_end_date: contract.end_date
      }

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_path(conn, :index), params)

      assert resp = json_response(conn, 200)["data"]
      assert length(resp) == 1
    end

    test "success contract list for non-NHS admin user", %{conn: conn} do
      msp()
      contractor_legal_entity = insert(:prm, :legal_entity)
      contract = insert(:prm, :contract, contractor_legal_entity_id: contractor_legal_entity.id, is_suspended: true)
      insert(:prm, :contract)

      params = %{
        id: contract.id,
        contractor_owner_id: contract.contractor_owner_id,
        nhs_signer_id: contract.nhs_signer_id,
        status: contract.status,
        is_suspended: true,
        date_from_start_date: contract.start_date,
        date_to_start_date: contract.start_date,
        date_from_end_date: contract.end_date,
        date_to_end_date: contract.end_date,
        contract_number: contract.contract_number
      }

      conn =
        conn
        |> put_client_id_header(contractor_legal_entity.id)
        |> get(contract_path(conn, :index), params)

      assert resp = json_response(conn, 200)["data"]
      assert length(resp) == 1
    end

    test "success filtering by nhs_signer_id", %{conn: conn} do
      msp()
      contractor_legal_entity = insert(:prm, :legal_entity)
      contract_in = insert(:prm, :contract, contractor_legal_entity_id: contractor_legal_entity.id)
      contract_out = insert(:prm, :contract, contractor_legal_entity_id: contractor_legal_entity.id)

      params = %{nhs_signer_id: contract_in.nhs_signer_id}

      conn =
        conn
        |> put_client_id_header(contractor_legal_entity.id)
        |> get(contract_path(conn, :index), params)

      assert resp = json_response(conn, 200)["data"]

      contract_ids = Enum.map(resp, fn item -> Map.get(item, "id") end)
      assert contract_in.id in contract_ids
      refute contract_out.id in contract_ids
    end
  end

  describe "terminate contract" do
    def terminate_response_fields do
      ~w(
      status
      status_reason
      is_suspended
      updated_by
      updated_at
    )
    end

    test "legal entity terminate verified contract", %{conn: conn} do
      msp()
      contract = insert(:prm, :contract)
      params = %{"status_reason" => "Period of contract is wrong"}

      resp =
        conn
        |> put_client_id_header(contract.contractor_legal_entity_id)
        |> patch(contract_path(conn, :terminate, contract.id), params)
        |> json_response(200)

      assert resp["data"]["status"] == Contract.status(:terminated)
      assert resp["data"]["status_reason"] == "Period of contract is wrong"
      Enum.each(terminate_response_fields(), fn field -> assert %{^field => _} = resp["data"] end)
    end

    test "NHS terminate verified contract", %{conn: conn} do
      nhs()
      contract = insert(:prm, :contract)
      params = %{"status_reason" => "Period of contract is wrong"}

      resp =
        conn
        |> put_client_id_header(contract.nhs_legal_entity_id)
        |> patch(contract_path(conn, :terminate, contract.id), params)
        |> json_response(200)

      assert resp["data"]["status"] == Contract.status(:terminated)
      assert resp["data"]["status_reason"] == "Period of contract is wrong"
      Enum.each(terminate_response_fields(), fn field -> assert %{^field => _} = resp["data"] end)
    end

    test "NHS terminate not verified contract", %{conn: conn} do
      nhs()
      contract = insert(:prm, :contract, status: "SIGNED")
      params = %{"status_reason" => "Period of contract is wrong"}

      resp =
        conn
        |> put_client_id_header(contract.nhs_legal_entity_id)
        |> patch(contract_path(conn, :terminate, contract.id), params)

      assert json_response(resp, 409)
    end

    test "NHS terminate contract without request data", %{conn: conn} do
      nhs()
      contract = insert(:prm, :contract)

      resp =
        conn
        |> put_client_id_header(contract.nhs_legal_entity_id)
        |> patch(contract_path(conn, :terminate, contract.id), %{})

      assert json_response(resp, 422)
    end

    test "terminate contract with wrong client id", %{conn: conn} do
      nhs()
      contract = insert(:prm, :contract)
      params = %{"status_reason" => "Period of contract is wrong"}

      resp =
        conn
        |> put_client_id_header(UUID.generate())
        |> patch(contract_path(conn, :terminate, contract.id), params)

      assert json_response(resp, 403)
    end

    test "terminate contract not exists", %{conn: conn} do
      nhs()
      params = %{"status_reason" => "Period of contract is wrong"}

      resp =
        conn
        |> put_client_id_header(UUID.generate())
        |> patch(contract_path(conn, :terminate, UUID.generate()), params)

      assert json_response(resp, 404)
    end
  end

  describe "update employees" do
    test "contract_employee not found", %{conn: conn} do
      nhs()

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> patch(contract_path(conn, :update, UUID.generate()))

      assert json_response(conn, 404)
    end

    test "failed to decode signed content", %{conn: conn} do
      nhs()
      contract = insert(:prm, :contract)

      params = %{
        "signed_content" => Jason.encode!(%{}),
        "signed_content_encoding" => "base64"
      }

      invalid_signed_content()

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> patch(contract_path(conn, :update, contract.id), params)

      assert resp = json_response(conn, 422)

      assert %{
               "invalid" => [
                 %{
                   "rules" => [%{"rule" => "invalid", "params" => [], "description" => "Not a base64 string"}],
                   "entry_type" => "json_data_property",
                   "entry" => "$.signed_content"
                 }
               ]
             } = resp["error"]
    end

    test "invalid drfo", %{conn: conn} do
      nhs()
      contract = insert(:prm, :contract)
      division = insert(:prm, :division)
      employee = insert(:prm, :employee)
      employee_id = employee.id
      party_user = insert(:prm, :party_user)

      content = %{
        "employee_id" => employee_id,
        "division_id" => division.id,
        "declaration_limit" => 10,
        "staff_units" => 0.33
      }

      params = %{
        "signed_content" =>
          content
          |> Jason.encode!()
          |> Base.encode64(),
        "signed_content_encoding" => "base64"
      }

      drfo_signed_content(content, nil)

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> put_consumer_id_header(party_user.user_id)
        |> patch(contract_path(conn, :update, contract.id), params)

      assert resp = json_response(conn, 422)

      assert %{
               "message" => "Invalid drfo"
             } = resp["error"]
    end

    test "invalid status", %{conn: conn} do
      nhs()
      contract = insert(:prm, :contract, status: Contract.status(:terminated))
      division = insert(:prm, :division)
      employee = insert(:prm, :employee)
      employee_id = employee.id
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division.id)
      party_user = insert(:prm, :party_user)

      content = %{
        "employee_id" => employee_id,
        "division_id" => division.id,
        "declaration_limit" => 10,
        "staff_units" => 0.33
      }

      params = %{
        "signed_content" =>
          content
          |> Jason.encode!()
          |> Base.encode64(),
        "signed_content_encoding" => "base64"
      }

      drfo_signed_content(content, party_user.party.tax_id)

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> put_consumer_id_header(party_user.user_id)
        |> Plug.Conn.put_req_header("drfo", party_user.party.tax_id)
        |> patch(contract_path(conn, :update, contract.id), params)

      assert resp = json_response(conn, 409)
      assert "Not active contract can't be updated" == resp["error"]["message"]
    end

    test "inactive division", %{conn: conn} do
      nhs()
      contract_request = insert(:il, :contract_request)
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)
      legal_entity = insert(:prm, :legal_entity, id: contract.contractor_legal_entity_id)
      division = insert(:prm, :division, legal_entity: legal_entity, status: Division.status(:inactive))
      employee = insert(:prm, :employee, legal_entity: legal_entity)
      employee_id = employee.id
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division.id)

      insert(
        :prm,
        :contract_employee,
        contract_id: contract.id,
        employee_id: employee_id,
        division_id: division.id,
        declaration_limit: 2000
      )

      party_user = insert(:prm, :party_user)

      content = %{
        "employee_id" => employee_id,
        "division_id" => division.id,
        "declaration_limit" => 10,
        "staff_units" => 0.33
      }

      params = %{
        "signed_content" =>
          content
          |> Jason.encode!()
          |> Base.encode64(),
        "signed_content_encoding" => "base64"
      }

      drfo_signed_content(content, party_user.party.tax_id)

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> put_consumer_id_header(party_user.user_id)
        |> Plug.Conn.put_req_header("drfo", party_user.party.tax_id)
        |> patch(contract_path(conn, :update, contract.id), params)

      assert resp = json_response(conn, 422)
      assert "Division must be active and within current legal_entity" == resp["error"]["message"]
    end

    test "contract and employee legal_entity_id mismatch", %{conn: conn} do
      nhs()
      contract_request = insert(:il, :contract_request)
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)
      legal_entity = insert(:prm, :legal_entity, id: contract.contractor_legal_entity_id)
      division = insert(:prm, :division, legal_entity: legal_entity)
      employee = insert(:prm, :employee)
      employee_id = employee.id
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division.id)

      insert(
        :prm,
        :contract_employee,
        contract_id: contract.id,
        employee_id: employee_id,
        division_id: division.id,
        declaration_limit: 2000
      )

      party_user = insert(:prm, :party_user)

      content = %{
        "employee_id" => employee_id,
        "division_id" => division.id,
        "declaration_limit" => 10,
        "staff_units" => 0.33
      }

      params = %{
        "signed_content" =>
          content
          |> Jason.encode!()
          |> Base.encode64(),
        "signed_content_encoding" => "base64"
      }

      drfo_signed_content(content, party_user.party.tax_id)

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> put_consumer_id_header(party_user.user_id)
        |> Plug.Conn.put_req_header("drfo", party_user.party.tax_id)
        |> patch(contract_path(conn, :update, contract.id), params)

      assert resp = json_response(conn, 422)
      assert "Employee and contract legal_entity_id mismatch" == resp["error"]["message"]
    end

    test "succes update employee", %{conn: conn} do
      nhs()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _, _ ->
        {:ok, "success"}
      end)

      contract_request = insert(:il, :contract_request)
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)
      legal_entity = insert(:prm, :legal_entity, id: contract.contractor_legal_entity_id)
      division = insert(:prm, :division, legal_entity: legal_entity)
      employee = insert(:prm, :employee, legal_entity: legal_entity)
      employee_id = employee.id
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division.id)

      insert(
        :prm,
        :contract_employee,
        contract_id: contract.id,
        employee_id: employee_id,
        division_id: division.id,
        declaration_limit: 2000
      )

      party_user = insert(:prm, :party_user)

      content = %{
        "employee_id" => employee_id,
        "division_id" => division.id,
        "declaration_limit" => 10,
        "staff_units" => 0.33
      }

      params = %{
        "signed_content" =>
          content
          |> Jason.encode!()
          |> Base.encode64(),
        "signed_content_encoding" => "base64"
      }

      drfo_signed_content(content, party_user.party.tax_id)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)
        |> Plug.Conn.put_req_header("drfo", party_user.party.tax_id)
        |> patch(contract_path(conn, :update, contract.id), params)

      assert resp = json_response(conn, 200)

      assert [%{"employee" => %{"id" => ^employee_id}, "declaration_limit" => 10, "staff_units" => 0.33}] =
               resp["data"]["contractor_employee_divisions"]
    end

    test "succes update employee set inactive", %{conn: conn} do
      nhs()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _, _ ->
        {:ok, "success"}
      end)

      contract_request = insert(:il, :contract_request)
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)
      legal_entity = insert(:prm, :legal_entity, id: contract.contractor_legal_entity_id)
      division = insert(:prm, :division, legal_entity: legal_entity)
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division.id)

      [employee_id_active, employee_id_inactive] =
        Enum.reduce(1..2, [], fn _, acc ->
          employee = insert(:prm, :employee, legal_entity: legal_entity)

          insert(
            :prm,
            :contract_employee,
            contract_id: contract.id,
            employee_id: employee.id,
            division_id: division.id,
            declaration_limit: 2000
          )

          [employee.id | acc]
        end)

      party_user = insert(:prm, :party_user)

      content = %{
        "employee_id" => employee_id_inactive,
        "division_id" => division.id,
        "is_active" => false
      }

      params = %{
        "signed_content" =>
          content
          |> Jason.encode!()
          |> Base.encode64(),
        "signed_content_encoding" => "base64"
      }

      drfo_signed_content(content, party_user.party.tax_id)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)
        |> Plug.Conn.put_req_header("drfo", party_user.party.tax_id)
        |> patch(contract_path(conn, :update, contract.id), params)

      assert resp = json_response(conn, 200)

      assert [%{"employee" => %{"id" => ^employee_id_active}}] = resp["data"]["contractor_employee_divisions"]
    end

    test "succes insert employees", %{conn: conn} do
      nhs()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _, _ ->
        {:ok, "success"}
      end)

      contract_request = insert(:il, :contract_request)
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)
      legal_entity = insert(:prm, :legal_entity, id: contract.contractor_legal_entity_id)
      division = insert(:prm, :division, legal_entity: legal_entity)
      employee = insert(:prm, :employee, legal_entity: legal_entity)
      employee_id = employee.id
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division.id)
      party_user = insert(:prm, :party_user)

      content = %{
        "employee_id" => employee_id,
        "division_id" => division.id,
        "declaration_limit" => 10,
        "staff_units" => 0.33
      }

      params = %{
        "signed_content" =>
          content
          |> Jason.encode!()
          |> Base.encode64(),
        "signed_content_encoding" => "base64"
      }

      drfo_signed_content(content, party_user.party.tax_id)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)
        |> Plug.Conn.put_req_header("drfo", party_user.party.tax_id)
        |> patch(contract_path(conn, :update, contract.id), params)

      assert resp = json_response(conn, 200)

      assert [%{"employee" => %{"id" => ^employee_id}, "declaration_limit" => 10, "staff_units" => 0.33}] =
               resp["data"]["contractor_employee_divisions"]
    end

    test "update employee limit validation failed", %{conn: conn} do
      nhs()
      contract_request = insert(:il, :contract_request)
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)
      legal_entity = insert(:prm, :legal_entity, id: contract.contractor_legal_entity_id)
      division = insert(:prm, :division, legal_entity: legal_entity)
      employee = insert(:prm, :employee, legal_entity: legal_entity)
      employee_id = employee.id
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division.id)

      insert(
        :prm,
        :contract_employee,
        contract_id: contract.id,
        employee_id: employee_id,
        division_id: division.id,
        declaration_limit: 2000
      )

      party_user = insert(:prm, :party_user)

      content = %{
        "employee_id" => employee_id,
        "division_id" => division.id,
        "declaration_limit" => 10000,
        "staff_units" => 0.33
      }

      params = %{
        "signed_content" =>
          content
          |> Jason.encode!()
          |> Base.encode64(),
        "signed_content_encoding" => "base64"
      }

      drfo_signed_content(content, party_user.party.tax_id)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)
        |> Plug.Conn.put_req_header("drfo", party_user.party.tax_id)
        |> patch(contract_path(conn, :update, contract.id), params)

      assert resp = json_response(conn, 422)
      assert get_in(resp, ~w(error message)) == "declaration_limit is not allowed for employee speciality"
    end

    test "insert employees limit validation failed", %{conn: conn} do
      nhs()
      contract_request = insert(:il, :contract_request)
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)
      legal_entity = insert(:prm, :legal_entity, id: contract.contractor_legal_entity_id)
      division = insert(:prm, :division, legal_entity: legal_entity)
      employee = insert(:prm, :employee, legal_entity: legal_entity)
      employee_id = employee.id
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division.id)
      party_user = insert(:prm, :party_user)

      content = %{
        "employee_id" => employee_id,
        "division_id" => division.id,
        "declaration_limit" => 10000,
        "staff_units" => 0.33
      }

      params = %{
        "signed_content" =>
          content
          |> Jason.encode!()
          |> Base.encode64(),
        "signed_content_encoding" => "base64"
      }

      drfo_signed_content(content, party_user.party.tax_id)

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> put_consumer_id_header(party_user.user_id)
        |> Plug.Conn.put_req_header("drfo", party_user.party.tax_id)
        |> patch(contract_path(conn, :update, contract.id), params)

      assert resp = json_response(conn, 422)
      assert get_in(resp, ~w(error message)) == "declaration_limit is not allowed for employee speciality"
    end

    test "client_id validation failed during update_employee", %{conn: conn} do
      msp()
      contract_request = insert(:il, :contract_request)
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)
      legal_entity = insert(:prm, :legal_entity, id: contract.contractor_legal_entity_id)
      legal_entity_out = insert(:prm, :legal_entity)
      division = insert(:prm, :division, legal_entity: legal_entity)
      employee = insert(:prm, :employee, legal_entity: legal_entity_out)
      employee_id = employee.id
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division.id)

      insert(
        :prm,
        :contract_employee,
        contract_id: contract.id,
        employee_id: employee_id,
        division_id: division.id,
        declaration_limit: 2000
      )

      party_user = insert(:prm, :party_user)

      content = %{
        "employee_id" => employee_id,
        "division_id" => division.id,
        "declaration_limit" => 10,
        "staff_units" => 0.33
      }

      params = %{
        "signed_content" =>
          content
          |> Jason.encode!()
          |> Base.encode64(),
        "signed_content_encoding" => "base64"
      }

      drfo_signed_content(content, party_user.party.tax_id)

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> put_consumer_id_header(party_user.user_id)
        |> Plug.Conn.put_req_header("drfo", party_user.party.tax_id)
        |> patch(contract_path(conn, :update, contract.id), params)

      assert resp = json_response(conn, 422)
      assert get_in(resp, ~w(error message)) == "Employee should be active Doctor within current legal_entity_id"
    end

    test "client_id validation failed during insert_employee", %{conn: conn} do
      msp()
      contract_request = insert(:il, :contract_request)
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)
      legal_entity = insert(:prm, :legal_entity, id: contract.contractor_legal_entity_id)
      legal_entity_out = insert(:prm, :legal_entity)
      division = insert(:prm, :division, legal_entity: legal_entity)
      employee = insert(:prm, :employee, legal_entity: legal_entity_out)
      employee_id = employee.id
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division.id)
      party_user = insert(:prm, :party_user)

      content = %{
        "employee_id" => employee_id,
        "division_id" => division.id,
        "declaration_limit" => 10,
        "staff_units" => 0.33
      }

      params = %{
        "signed_content" =>
          content
          |> Jason.encode!()
          |> Base.encode64(),
        "signed_content_encoding" => "base64"
      }

      drfo_signed_content(content, party_user.party.tax_id)

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> put_consumer_id_header(party_user.user_id)
        |> Plug.Conn.put_req_header("drfo", party_user.party.tax_id)
        |> patch(contract_path(conn, :update, contract.id), params)

      assert resp = json_response(conn, 422)
      assert get_in(resp, ~w(error message)) == "Employee should be active Doctor within current legal_entity_id"
    end
  end

  describe "get printout_form" do
    test "success get printout_form", %{conn: conn} do
      nhs()

      expect(MediaStorageMock, :create_signed_url, 2, fn _, _, _, _, _ ->
        {:ok, %{"data" => %{"secret_url" => "http://localhost/good_upload_1"}}}
      end)

      printout_content = "<html></html>"

      legal_entity_signer = insert(:prm, :legal_entity, edrpou: "10002000")

      expect(MediaStorageMock, :get_signed_content, 2, fn _ ->
        {:ok, %{body: "", status_code: 200}}
      end)

      %{id: contract_request_id} =
        contract_request =
        insert(
          :il,
          :contract_request,
          printout_content: printout_content
        )

      %{id: contract_id} =
        insert(
          :prm,
          :contract,
          status: Contract.status(:verified),
          contract_request_id: contract_request_id
        )

      content =
        contract_request
        |> Jason.encode!()
        |> Jason.decode!()

      edrpou_signed_content(content, legal_entity_signer.edrpou)

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_path(conn, :printout_content, contract_id))

      assert resp = json_response(conn, 200)
      assert %{"id" => contract_id, "printout_content" => printout_content} == resp["data"]
    end
  end

  describe "show contract employees" do
    test "finds contract successfully and nhs can see any contracts", %{conn: conn} do
      nhs()
      %{id: client_id} = insert(:prm, :legal_entity)

      contract_request = insert(:il, :contract_request)
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)
      division = insert(:prm, :division)
      employee = insert(:prm, :employee)
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division.id)

      for _ <- 1..3 do
        insert(
          :prm,
          :contract_employee,
          contract_id: contract.id,
          employee_id: employee.id,
          division_id: division.id,
          declaration_limit: 2000
        )
      end

      response =
        conn
        |> put_client_id_header(client_id)
        |> get(contract_path(conn, :show_employees, contract.id))
        |> json_response(200)

      assert length(response["data"]) == 3

      Enum.map(response["data"], fn contract_employee ->
        assert Map.get(contract_employee, "contract_id") == contract.id
      end)

      assert %{"total_entries" => 3} = response["paging"]
    end

    test "ensure MSP has access to own contracts", %{conn: conn} do
      msp()
      contractor_legal_entity = insert(:prm, :legal_entity)
      contract_request = insert(:il, :contract_request)

      contract =
        insert(
          :prm,
          :contract,
          contractor_legal_entity_id: contractor_legal_entity.id,
          contract_request_id: contract_request.id
        )

      assert conn
             |> put_client_id_header(contractor_legal_entity.id)
             |> get(contract_path(conn, :show_employees, contract.id))
             |> json_response(200)
    end

    test "ensure MSP has no access to other contracts", %{conn: conn} do
      msp()
      contractor_legal_entity = insert(:prm, :legal_entity)
      contract = insert(:prm, :contract)

      assert %{"error" => %{"type" => "forbidden", "message" => _}} =
               conn
               |> put_client_id_header(contractor_legal_entity.id)
               |> get(contract_path(conn, :show_employees, contract.id))
               |> json_response(403)
    end

    test "not found", %{conn: conn} do
      msp()
      %{id: client_id} = insert(:prm, :legal_entity)

      assert %{"error" => %{"type" => "not_found"}} =
               conn
               |> put_client_id_header(client_id)
               |> get(contract_path(conn, :show_employees, UUID.generate()))
               |> json_response(404)
    end

    test "client is not active", %{conn: conn} do
      msp()
      %{id: client_id} = insert(:prm, :legal_entity, is_active: false)

      assert %{"error" => %{"type" => "forbidden", "message" => "Client is not active"}} =
               conn
               |> put_client_id_header(client_id)
               |> get(contract_path(conn, :show_employees, UUID.generate()))
               |> json_response(403)
    end

    test "finds contract successfully with search params", %{conn: conn} do
      nhs()
      %{id: client_id} = insert(:prm, :legal_entity)

      contract_request = insert(:il, :contract_request)
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)
      division_1 = insert(:prm, :division)
      division_2 = insert(:prm, :division)
      employee = insert(:prm, :employee)
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division_1.id)
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division_2.id)

      # contract_employee_in_1
      insert(
        :prm,
        :contract_employee,
        contract_id: contract.id,
        employee_id: employee.id,
        division_id: division_1.id,
        declaration_limit: 2000,
        end_date: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
      )

      # contract_employee_out_1
      insert(
        :prm,
        :contract_employee,
        contract_id: contract.id,
        employee_id: employee.id,
        division_id: division_2.id,
        declaration_limit: 2000
      )

      # contract_employee_out_2
      insert(
        :prm,
        :contract_employee,
        contract_id: contract.id,
        employee_id: employee.id,
        division_id: division_1.id,
        declaration_limit: 2000
      )

      search_params = %{
        "employee_id" => employee.id,
        "division_id" => division_1.id,
        "is_active" => false
      }

      response =
        conn
        |> put_client_id_header(client_id)
        |> get(contract_path(conn, :show_employees, contract.id), search_params)
        |> json_response(200)

      assert length(response["data"]) == 1
    end

    test "ignore invalid search params", %{conn: conn} do
      nhs()
      %{id: client_id} = insert(:prm, :legal_entity)

      contract_request = insert(:il, :contract_request)
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)
      division = insert(:prm, :division)
      employee = insert(:prm, :employee)
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division.id)

      for _ <- 1..3 do
        insert(
          :prm,
          :contract_employee,
          contract_id: contract.id,
          employee_id: employee.id,
          division_id: division.id,
          declaration_limit: 2000
        )
      end

      search_params = %{"test" => true}

      response =
        conn
        |> put_client_id_header(client_id)
        |> get(contract_path(conn, :show_employees, contract.id), search_params)
        |> json_response(200)

      assert length(response["data"]) == 3

      Enum.map(response["data"], fn contract_employee ->
        assert Map.get(contract_employee, "contract_id") == contract.id
      end)

      assert %{"total_entries" => 3} = response["paging"]
    end

    test "insure is_active search param is true by default, start_date and end_date are date format", %{conn: conn} do
      nhs()
      %{id: client_id} = insert(:prm, :legal_entity)

      contract_request = insert(:il, :contract_request)
      contract = insert(:prm, :contract, contract_request_id: contract_request.id)
      division = insert(:prm, :division)
      employee = insert(:prm, :employee)
      insert(:prm, :contract_division, contract_id: contract.id, division_id: division.id)

      start_date = NaiveDateTime.add(NaiveDateTime.utc_now(), -60 * 60 * 24)
      end_date = NaiveDateTime.add(NaiveDateTime.utc_now(), 60 * 60 * 24)

      for _ <- 1..2 do
        insert(
          :prm,
          :contract_employee,
          contract_id: contract.id,
          employee_id: employee.id,
          division_id: division.id,
          declaration_limit: 2000,
          start_date: start_date,
          end_date: end_date
        )
      end

      insert(
        :prm,
        :contract_employee,
        contract_id: contract.id,
        employee_id: employee.id,
        division_id: division.id,
        declaration_limit: 2000,
        end_date: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
      )

      response =
        conn
        |> put_client_id_header(client_id)
        |> get(contract_path(conn, :show_employees, contract.id))
        |> json_response(200)

      assert length(response["data"]) == 2

      Enum.map(response["data"], fn contract_employee ->
        assert Map.get(contract_employee, "contract_id") == contract.id
        assert Map.get(contract_employee, "start_date") == Date.utc_today() |> Date.add(-1) |> Date.to_string()
        assert Map.get(contract_employee, "end_date") == Date.utc_today() |> Date.add(1) |> Date.to_string()
      end)

      assert %{"total_entries" => 2} = response["paging"]
    end
  end
end
