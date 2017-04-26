defmodule EHealth.MockServer do
  @moduledoc false
  use Plug.Router
  plug :match
  plug Plug.Parsers, parsers: [:json],
                     pass:  ["application/json"],
                     json_decoder: Poison
  plug :dispatch

  # Legal Entitity
  get "/legal_entities" do
    Plug.Conn.send_resp(conn, 200, Poison.encode!([%{
      "id" => "d290f1ee",
      "name" => "Клініка Борис",
      "short_name" => "Борис",
      "type" => "MSP",
      "edrpou" => "37367387",
      "addresses" => [
         %{
          "type" => "RESIDENCE",
          "country" => "UA",
          "area" => "Житомирська",
          "region" => "Бердичівський",
          "settlement" => "Київ",
          "settlement_type" => "CITY",
          "settlement_id" => "43432432",
          "street_type" => "STREET",
          "street" => "вул. Ніжинська",
          "building" => "15",
          "apartment" => "23",
          "zip" => "02090",
        }
      ],
      "phones" => [
         %{
          "type" => "MOBILE",
          "number" => "+380503410870"
        }
      ],
      "email" => "email@example.com",
      "active" => true,
      "public_name" => "Клініка Борис",
      "kved" => [
        "86.1"
      ],
      "status" => "VERIFIED",
      "owner_property_type" => "state",
      "legal_form" => "ПІДПРИЄМЕЦЬ-ФІЗИЧНА ОСОБА",
      "medical_service_provider" => %{
        "licenses" => [
           %{
            "license_number" => "fd123443",
            "issued_by" => "Кваліфікацйна комісія",
            "issued_date" => "2017",
            "expiry_date" => "2017",
            "kved" => "86.1",
            "what_licensed" => "реалізація наркотичних засобів"
          }
        ],
        "accreditation" =>  %{
          "category" => "друга",
          "issued_date" => "2017",
          "expiry_date" => "2017",
          "order_no" => "fd123443",
          "order_date" => "2017"
        }
      },
      "inserted_at" => "1991-08-19T00.00.00.000Z",
      "inserted_by" => "userid",
      "updated_at" => "1991-08-19T00.00.00.000Z",
      "updated_by" => "userid"
    }]))
  end

  def render(resource, conn, status) do
    conn =
      conn
      |> Plug.Conn.put_status(status)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, get_resp_body(resource, conn))
  end

  def get_resp_body(resource, conn), do: resource |> EView.wrap_body(conn) |> Poison.encode!()

end
