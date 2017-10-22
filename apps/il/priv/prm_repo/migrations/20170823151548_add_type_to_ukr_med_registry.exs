defmodule Il.PRMRepo.Migrations.AddTypeToUkrMedRegistry do
  use Ecto.Migration

  alias Il.PRM.Registries.Schema, as: Registry

  def change do
    alter table(:ukr_med_registries) do
      add :type, :string, null: false, default: Registry.type(:msp)
    end
  end
end
