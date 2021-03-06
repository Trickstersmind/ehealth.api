defmodule EHealth.Web.MedicationRequestView do
  @moduledoc false

  use EHealth.Web, :view
  alias EHealth.Web.{LegalEntityView, MedicationRequestRequestView}

  def render("index.json", %{medication_requests: medication_requests}) do
    render_many(medication_requests, __MODULE__, "show.json")
  end

  def render("show.json", %{medication_request: medication_request}) do
    legal_entity = medication_request["legal_entity"]
    created_at = Timex.parse!(medication_request["created_at"], "{YYYY}-{0M}-{D}")
    person = MedicationRequestRequestView.render_person(medication_request["person"], created_at)

    medication_request
    |> Map.take(~w(
      id
      status
      request_number
      created_at
      started_at
      ended_at
      dispense_valid_from
      dispense_valid_to
    ))
    |> Map.put("legal_entity", render_one(legal_entity, LegalEntityView, "show_reimbursement.json"))
    |> Map.put("employee", render_one(medication_request["employee"], __MODULE__, "employee.json", as: :employee))
    |> Map.put("division", render_one(medication_request["division"], __MODULE__, "division.json", as: :division))
    |> Map.put(
      "medical_program",
      render_one(medication_request["medical_program"], __MODULE__, "medical_program.json", as: :medical_program)
    )
    |> Map.put("medication_info", render_one(medication_request, __MODULE__, "medication_info.json"))
    |> Map.put("person", person)
  end

  def render("medication_info.json", %{medication_request: medication_request}) do
    medication = medication_request["medication"]
    ingredient = Enum.find(medication.ingredients, &Map.get(&1, :is_primary))

    medication_request
    |> Map.take(~w(medication_qty))
    |> Map.put("form", medication.form)
    |> Map.put("medication_id", medication.id)
    |> Map.put("medication_name", medication.name)
    |> Map.put("dosage", ingredient.dosage)
  end

  def render("qualify.json", %{medical_programs: medical_programs, validations: validations}) do
    Enum.map(medical_programs, fn program ->
      {_, validation} = Enum.find(validations, fn {id, _} -> id == program.id end)

      {status, reason, participants} =
        case validation do
          :ok ->
            {"VALID", "",
             render_many(
               program.program_medications,
               __MODULE__,
               "program_medication.json",
               as: :program_medication
             )}

          {:error, reason} ->
            {"INVALID", reason, []}
        end

      %{
        "program_id" => program.id,
        "program_name" => program.name,
        "status" => status,
        "rejection_reason" => reason,
        "participants" => participants
      }
    end)
  end

  def render("program_medication.json", %{program_medication: program_medication}) do
    medication = program_medication.medication

    %{
      "medication_id" => medication.id,
      "medication_name" => medication.name,
      "form" => medication.form,
      "manufacturer" => medication.manufacturer,
      "reimbursement_amount" => program_medication.reimbursement["reimbursement_amount"]
    }
  end

  def render("division.json", %{division: division}) do
    division
    |> Map.take(~w(
          id
          name
          type
          addresses
          phones
          email
          external_id
          legal_entity_id
          working_hours
        )a)
    |> Map.put(:location, to_coordinates(division.location))
  end

  def render("employee.json", %{employee: employee}) do
    party = Map.take(employee.party, ~w(
      id
      first_name
      last_name
      second_name
      phones
    )a)

    employee
    |> Map.take(~w(id position)a)
    |> Map.put(:party, party)
  end

  def render("medical_program.json", %{medical_program: medical_program}) do
    Map.take(medical_program, ~w(id name)a)
  end

  def to_coordinates(%Geo.Point{coordinates: {lng, lat}}) do
    %{
      longitude: lng,
      latitude: lat
    }
  end

  def to_coordinates(field), do: field
end
