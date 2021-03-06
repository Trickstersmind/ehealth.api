defmodule EHealth.OPSFactories.DeclarationFactory do
  @moduledoc false

  alias Ecto.UUID

  defmacro __using__(_opts) do
    quote do
      def declaration_factory do
        day = 60 * 60 * 24
        start_date = NaiveDateTime.utc_now() |> NaiveDateTime.add(-10 * day, :seconds)
        end_date = NaiveDateTime.add(start_date, day, :seconds)

        %{
          id: UUID.generate(),
          declaration_request_id: UUID.generate(),
          start_date: to_string(start_date),
          end_date: end_date,
          status: "active",
          signed_at: to_string(start_date),
          created_by: UUID.generate(),
          updated_by: UUID.generate(),
          employee_id: UUID.generate(),
          person_id: UUID.generate(),
          division_id: UUID.generate(),
          legal_entity_id: UUID.generate(),
          is_active: true,
          scope: "",
          seed: "some seed",
          declaration_number: sequence(:declaration_number, &"test-declaration-number-#{&1}"),
          reason: "",
          reason_description: ""
        }
      end
    end
  end
end
