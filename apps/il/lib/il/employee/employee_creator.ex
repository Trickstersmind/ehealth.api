defmodule Il.Employee.EmployeeCreator do
  @moduledoc """
  Creates new employee from valid employee request
  """

  import Il.Utils.Connection, only: [get_consumer_id: 1]

  alias Scrivener.Page
  alias Il.Employee.Request
  alias Il.PRM.Employees
  alias Il.PRM.Parties.Schema, as: Party
  alias Il.PRM.Employees.Schema, as: Employee
  alias Il.PRM.PartyUsers.Schema, as: PartyUser
  alias Il.PRM.Parties
  alias Il.PRM.PartyUsers
  alias Il.Employee.EmployeeUpdater

  require Logger

  @type_owner Employee.type(:owner)
  @type_pharmacy_owner Employee.type(:pharmacy_owner)
  @status_approved Employee.status(:approved)

  def create(%Request{data: data} = employee_request, req_headers) do
    party = Map.fetch!(data, "party")
    search_params = %{tax_id: party["tax_id"], birth_date: party["birth_date"]}
    user_id = get_consumer_id(req_headers)

    with %Page{} = paging <- Parties.list_parties(search_params),
         :ok <- check_party_user(user_id, paging.entries),
         {:ok, party} <- create_or_update_party(paging.entries, party, req_headers),
         {:ok, employee} <- create_employee(party, employee_request, req_headers)
    do
      deactivate_employee_owners(employee, req_headers)
    end
  end

  @doc """
  Created new party
  """
  def create_or_update_party([], data, req_headers) do
    with data <- put_inserted_by(data, req_headers),
         {:ok, party} <- Parties.create_party(data)
    do
      create_party_user(party, req_headers)
    end
  end

  @doc """
  Updates party
  """
  def create_or_update_party([%Party{} = party], data, req_headers) do
    with {:ok, party} <- Parties.update_party(party, data) do
      create_party_user(party, req_headers)
    end
  end

  def create_party_user(%Party{id: id, users: users} = party, headers) do
    user_ids = Enum.map(users, &Map.get(&1, :user_id))
    case Enum.member?(user_ids, get_consumer_id(headers)) do
      true ->
        {:ok, party}
      false ->
        case PartyUsers.create_party_user(id, get_consumer_id(headers)) do
          {:ok, _} -> {:ok, party}
          {:error, _} = err -> err
        end
    end
  end

  def create_employee(%Party{id: id}, %Request{data: employee_request}, req_headers) do
    data = %{
      "status" => @status_approved,
      "is_active" => true,
      "party_id" => id,
      "legal_entity_id" => employee_request["legal_entity_id"],
    }

    data
    |> Map.merge(employee_request)
    |> put_inserted_by(req_headers)
    |> Employees.create_employee(get_consumer_id(req_headers))
  end
  def create_employee(err, _, _), do: err

  def deactivate_employee_owners(%Employee{employee_type: @type_owner} = employee, req_headers) do
    do_deactivate_employee_owners(employee, req_headers)
  end
  def deactivate_employee_owners(%Employee{employee_type: @type_pharmacy_owner} = employee, req_headers) do
    do_deactivate_employee_owners(employee, req_headers)
  end
  def deactivate_employee_owners(%Employee{} = employee, _req_headers), do: {:ok, employee}

  defp do_deactivate_employee_owners(%Employee{employee_type: type} = employee, req_headers) do
    %{
      legal_entity_id: employee.legal_entity_id,
      is_active: true,
      employee_type: type,
    }
    |> Employees.get_employees()
    |> deactivate_employees(employee, req_headers)
    {:ok, employee}
  end

  def deactivate_employees(%Page{entries: employees}, current_owner, headers) do
    Enum.each(employees, fn(%Employee{} = employee) ->
      case current_owner.id != employee.id do
        true -> deactivate_employee(employee, current_owner, headers)
        false -> :ok
      end
    end)
  end

  def deactivate_employee(%Employee{} = employee, current_owner, headers) do
    params = %{
      "updated_by" => get_consumer_id(headers),
      "is_active" => false,
    }

    with :ok <- EmployeeUpdater.revoke_user_auth_data(employee, [current_owner], headers) do
      Employees.update_employee(employee, params, get_consumer_id(headers))
    end
  end

  def put_inserted_by(data, req_headers) do
    map = %{
      "inserted_by" => get_consumer_id(req_headers),
      "updated_by" => get_consumer_id(req_headers),
    }
    Map.merge(data, map)
  end

  defp check_party_user(user_id, []) do
    with nil <- PartyUsers.get_party_users_by_user_id(user_id) do
      :ok
    else
      _ -> {:error, {:conflict, "Email is already used by another person"}}
    end
  end
  defp check_party_user(user_id, [%Party{id: party_id}]) do
    with nil <- PartyUsers.get_party_users_by_user_id(user_id) do
      :ok
    else
      %PartyUser{party: %Party{id: id}} when id == party_id -> :ok
      _ -> {:error, {:conflict, "Email is already used by another person"}}
    end
  end
end
