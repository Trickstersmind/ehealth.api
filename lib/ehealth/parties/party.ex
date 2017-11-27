defmodule EHealth.Parties.Party do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "parties" do
    field :first_name, :string
    field :last_name, :string
    field :second_name, :string
    field :birth_date, :date
    field :gender, :string
    field :tax_id, :string
    field :inserted_by, Ecto.UUID
    field :updated_by, Ecto.UUID

    embeds_many :phones, EHealth.PRM.Meta.Phone, on_replace: :delete
    embeds_many :documents, EHealth.PRM.Meta.Document, on_replace: :delete

    has_many :users, EHealth.PRM.PartyUsers.Schema, foreign_key: :party_id

    timestamps()
  end
end
