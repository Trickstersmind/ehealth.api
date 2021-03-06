defmodule EHealth.Validators.Signature do
  @moduledoc false

  alias EHealth.Employees
  alias EHealth.Employees.Employee
  alias EHealth.Parties
  alias EHealth.Parties.Party
  require Logger

  @signature_api Application.get_env(:ehealth, :api_resolvers)[:digital_signature]

  def validate(signed_content, encoding, headers, required_signatures \\ 1) do
    with {:ok, %{"data" => data}} <- @signature_api.decode_and_validate(signed_content, encoding, headers) do
      process_data(data, required_signatures)
    end
  end

  def check_drfo(%{"drfo" => drfo}, user_id, process) when not is_nil(drfo) do
    drfo = String.replace(drfo, " ", "")

    with %Party{tax_id: tax_id} <- Parties.get_by_user_id(user_id) do
      log_drfo(drfo, tax_id, process)

      if tax_id == drfo || translit_drfo(tax_id) == translit_drfo(drfo) do
        :ok
      else
        {:error, {:"422", "Does not match the signer drfo"}}
      end
    else
      _ -> {:error, {:forbidden, "User is not allowed to this action by client_id"}}
    end
  end

  def check_drfo(_, _, _), do: {:error, {:"422", "Invalid drfo"}}

  def check_drfo(%{"drfo" => drfo}, employee_id, path, process) when not is_nil(drfo) do
    drfo = String.replace(drfo, " ", "")

    with %Employee{party_id: party_id} <- Employees.get_by_id(employee_id),
         %Party{tax_id: tax_id} <- Parties.get_by_id(party_id),
         _ <- log_drfo(drfo, tax_id, process),
         true <- tax_id == drfo || translit_drfo(tax_id) == translit_drfo(drfo) do
      :ok
    else
      _ ->
        {:error,
         [
           {
             %{
               description: "Does not match the signer drfo",
               params: [],
               rule: :invalid
             },
             path
           }
         ]}
    end
  end

  def check_drfo(_, _, path, _) do
    {:error,
     [
       {
         %{
           description: "Invalid drfo",
           params: [],
           rule: :invalid
         },
         path
       }
     ]}
  end

  defp translit_drfo(drfo) do
    drfo
    |> Translit.translit()
    |> String.upcase()
  end

  defp log_drfo(drfo, tax_id, process) do
    Logger.info(fn ->
      Jason.encode!(%{
        "log_type" => "debug",
        "process" => process,
        "details" => %{
          "drfo" => drfo,
          "tax_id" => tax_id
        },
        "request_id" => Logger.metadata()[:request_id]
      })
    end)
  end

  defp process_data(
         %{"content" => content, "signatures" => signatures},
         required_signatures
       )
       when is_list(signatures) do
    if Enum.count(signatures) == required_signatures do
      # return the last signature (they are in reverse order)
      get_last_signer(content, List.first(signatures))
    else
      signer_msg = if required_signatures == 1, do: "signer", else: "signers"

      {:error,
       {:bad_request,
        "document must be signed by #{required_signatures} #{signer_msg} but contains #{Enum.count(signatures)} signatures"}}
    end
  end

  defp get_last_signer(content, %{"is_valid" => true, "signer" => signer}) do
    {:ok, %{"content" => content, "signer" => signer}}
  end

  defp get_last_signer(_, %{"is_valid" => false, "validation_error_message" => error}),
    do: {:error, {:bad_request, error}}
end
