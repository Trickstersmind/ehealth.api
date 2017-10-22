defmodule Il.PRMFactories.DivisionFactory do
  @moduledoc false

  alias Il.PRM.Divisions.Schema, as: Division

  defmacro __using__(_opts) do
    quote do
      alias Ecto.UUID

      def division_factory do
        %Il.PRM.Divisions.Schema{
          legal_entity: build(:legal_entity),
          addresses: [],
          phones: [],
          external_id: "7ae4bbd6-a9e7-4ce0-992b-6a1b18a262dc",
          type: Division.type(:clinic),
          email: "some",
          name: "some",
          status: Division.status(:active),
          mountain_group: false,
          location: %Geo.Point{coordinates: {50, 20}},
        }
      end
    end
  end
end
