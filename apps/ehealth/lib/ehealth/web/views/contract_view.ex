defmodule EHealth.Web.ContractView do
  @moduledoc false

  use EHealth.Web, :view
  alias EHealth.Web.ContractRequestView

  def render("index.json", %{contracts: contracts, references: references}) do
    Enum.map(contracts, fn contract ->
      render_one(contract, __MODULE__, "contract.json", references: references)
    end)
  end

  def render("contract.json", %{contract: contract, references: references}) do
    contract
    |> Map.take(~w(
      id
      start_date
      end_date
      status
      contractor_legal_entity_id
      contractor_base
      external_contractor_flag
      nhs_legal_entity_id
      nhs_signer_id
      nhs_signer_base
      nhs_contract_price
      issue_city
      contract_number
      is_suspended
      contract_request_id
    )a)
    |> Map.put(
      :contractor_owner,
      ContractRequestView.render_association(:employee, references, contract.contractor_owner_id)
    )
    |> Map.put(:contract_divisions, Enum.map(contract.contract_divisions, &render_association(:contract_division, &1)))
  end

  def render("show.json", %{contract: contract, references: references}) do
    contract
    |> Map.take(~w(
      id
      start_date
      end_date
      status
      contractor_base
      contractor_payment_details
      contractor_rmsp_amount
      external_contractor_flag
      external_contractors
      nhs_payment_method
      nhs_signer_base
      issue_city
      nhs_contract_price
      contract_number
      is_suspended
      contract_request_id
    )a)
    |> Map.put(
      :contractor_legal_entity,
      ContractRequestView.render_association(:legal_entity, references, contract.contractor_legal_entity_id)
    )
    |> Map.put(
      :nhs_legal_entity,
      ContractRequestView.render_association(:legal_entity, references, contract.nhs_legal_entity_id)
    )
    |> Map.put(
      :contractor_owner,
      ContractRequestView.render_association(:employee, references, contract.contractor_owner_id)
    )
    |> Map.put(
      :nhs_signer,
      ContractRequestView.render_association(:employee, references, contract.nhs_signer_id)
    )
    |> Map.put(
      :contractor_employee_divisions,
      render_association(
        :employee_divisions,
        references,
        contract.contract_employees || []
      )
    )
    |> Map.put(
      :contractor_divisions,
      render_association(:contractor_divisions, references, contract.contract_divisions || [])
    )
  end

  def render("terminate.json", %{contract: contract, references: references}) do
    contract
    |> Map.take(~w(
      id
      start_date
      end_date
      contractor_base
      contractor_payment_details
      contractor_rmsp_amount
      external_contractor_flag
      external_contractors
      nhs_signer_base
      nhs_contract_price
      nhs_payment_method
      status
      status_reason
      issue_city
      contract_number
      contract_request_id
      is_suspended
      updated_by
      updated_at
      )a)
    |> Map.put(
      :contractor_legal_entity,
      ContractRequestView.render_association(:legal_entity, references, contract.contractor_legal_entity_id)
    )
    |> Map.put(
      :nhs_legal_entity,
      ContractRequestView.render_association(:legal_entity, references, contract.nhs_legal_entity_id)
    )
    |> Map.put(
      :contractor_owner,
      ContractRequestView.render_association(:employee, references, contract.contractor_owner_id)
    )
    |> Map.put(
      :nhs_signer,
      ContractRequestView.render_association(:employee, references, contract.nhs_signer_id)
    )
    |> Map.put(
      :contractor_employee_divisions,
      render_association(
        :employee_divisions,
        references,
        contract.contract_employees || []
      )
    )
    |> Map.put(
      :contractor_divisions,
      render_association(:contractor_divisions, references, contract.contract_divisions || [])
    )
  end

  def render("printout_content.json", %{contract: contract, printout_content: printout_content}) do
    %{id: contract.id, printout_content: printout_content}
  end

  def render("show_employees.json", %{contract_employees: contract_employees, references: references}) do
    render_many(
      contract_employees,
      __MODULE__,
      "contract_employee.json",
      references: references,
      as: :contract_employee
    )
  end

  def render("contract_employee.json", %{contract_employee: contract_employee, references: references}) do
    contract_employee
    |> Map.take(~w(
      contract_id
      division_id
      staff_units
      declaration_limit
    )a)
    |> Map.put(:start_date, convert_naive_datetime_to_date(contract_employee.start_date))
    |> Map.put(:end_date, convert_naive_datetime_to_date(contract_employee.end_date))
    |> Map.put(
      :employee,
      render_association(:employee, references, contract_employee.employee_id)
    )
  end

  defp convert_naive_datetime_to_date(%NaiveDateTime{} = value), do: NaiveDateTime.to_date(value)
  defp convert_naive_datetime_to_date(value), do: value

  def render_association(:contract_division, contract_division) do
    Map.take(contract_division, ~w(id name)a)
  end

  def render_association(:employee_divisions, references, employee_divisions) do
    Enum.map(employee_divisions, fn employee_division ->
      employee_division
      |> Map.take(~w(division_id staff_units declaration_limit)a)
      |> Map.put(
        "employee",
        ContractRequestView.render_association(:employee_division, references, employee_division.employee_id)
      )
    end)
  end

  def render_association(:contractor_divisions, references, contractor_divisions) do
    Enum.map(contractor_divisions, &render_association(:division, references, &1))
  end

  def render_association(:division, references, contract_division) do
    with %{} = division <-
           references
           |> Map.get(:division)
           |> Map.get(contract_division.division_id) do
      Map.take(division, ~w(id name addresses phone email working_hours mountain_group phones)a)
    end
  end

  def render_association(:employee, references, id) do
    with %{} = employee <-
           references
           |> Map.get(:employee)
           |> Map.get(id) do
      employee
      |> Map.take(~w(id speciality)a)
      |> Map.put(:party, Map.take(employee.party, ~w(first_name last_name second_name)a))
    end
  end
end
