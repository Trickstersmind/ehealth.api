defmodule EHealth.OAuth.API do
  @moduledoc """
  OAuth service layer
  """

  import EHealth.Utils.Connection, only: [get_consumer_id: 1]

  alias EHealth.LegalEntities.LegalEntity

  require Logger

  @mithril_api Application.get_env(:ehealth, :api_resolvers)[:mithril]

  @doc """
  Creates a new Mithril client for MSP after successfully created a new Legal Entity
  """
  def put_client(%LegalEntity{} = legal_entity, client_type_id, redirect_uri, headers) do
    @mithril_api.put_client(
      %{
        "id" => legal_entity.id,
        "name" => legal_entity.name,
        "redirect_uri" => redirect_uri,
        "user_id" => get_consumer_id(headers),
        "client_type_id" => client_type_id
      },
      headers
    )
  end

  def create_user(%Ecto.Changeset{valid?: true, changes: %{password: password}}, email, headers) do
    @mithril_api.create_user(%{"password" => password, "email" => email}, headers)
  end

  def create_user(err, _email, _headers), do: err

  def get_client(id, headers) do
    id
    |> @mithril_api.get_client(headers)
    |> fetch_client_credentials(id)
  end

  defp fetch_client_credentials({:ok, %{"data" => data}}, id) when is_list(data) do
    data =
      case length(data) > 0 do
        true -> List.first(data)
        false -> %{}
      end

    fetch_client_credentials({:ok, %{"data" => data}}, id)
  end

  defp fetch_client_credentials({:ok, %{"data" => data}}, _id) do
    %{
      "client_id" => Map.get(data, "id"),
      "client_secret" => Map.get(data, "secret"),
      "redirect_uri" => Map.get(data, "redirect_uri")
    }
  end

  defp fetch_client_credentials({:error, response}, id) do
    Logger.error(fn ->
      Jason.encode!(%{
        "log_type" => "error",
        "message" => "Cannot create or find Mithril client for Legal Entity #{id} Response: #{inspect(response)}",
        "request_id" => Logger.metadata()[:request_id]
      })
    end)

    nil
  end
end
