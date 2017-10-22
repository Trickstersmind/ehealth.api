defmodule Il.DeclarationRequest.APITest do
  @moduledoc false

  use Il.Web.ConnCase, async: true
  import Il.DeclarationRequest.API
  import Il.SimpleFactory
  alias Il.DeclarationRequest
  alias Il.Repo

  describe "pending_declaration_requests/2" do
    test "returns pending requests" do
      existing_declaration_request_data = %{
        "person" => %{
          "tax_id" => "111"
        },
        "employee" => %{
          "id" => "222"
        },
        "legal_entity" => %{
          "id" => "333"
        }
      }

      {:ok, pending_declaration_req_1} = copy_declaration_request(existing_declaration_request_data, "NEW")
      {:ok, pending_declaration_req_2} = copy_declaration_request(existing_declaration_request_data, "APPROVED")

      query = pending_declaration_requests("111", "222", "333")

      assert [pending_declaration_req_1, pending_declaration_req_2] == Repo.all(query)
    end
  end

  def copy_declaration_request(template, status) do
    attrs = %{
      "status" => status,
      "data" => %{
        "person" => %{
          "tax_id" => get_in(template, ["person", "tax_id"])
        },
        "employee" => %{
          "id" => get_in(template, ["employee", "id"]),
        },
        "legal_entity" => %{
          "id" => get_in(template, ["legal_entity", "id"])
        }
      },
      "authentication_method_current" => %{
        "number" => "+380508887700",
        "type" => "OTP"
      },
      "documents" => [],
      "printout_content" => "Some fake content",
      "inserted_by" => Ecto.UUID.generate(),
      "updated_by" => Ecto.UUID.generate(),
      "declaration_id" => Ecto.UUID.generate()
    }

    allowed =
      attrs
      |> Map.keys
      |> Enum.map(&String.to_atom(&1))

    %DeclarationRequest{}
    |> Ecto.Changeset.cast(attrs, allowed)
    |> Repo.insert()
  end

  test "get_declaration_request_by_id!/1" do
    %{id: id} = fixture(DeclarationRequest)
    declaration_request = get_declaration_request_by_id!(id)
    assert id == declaration_request.id
  end
end
