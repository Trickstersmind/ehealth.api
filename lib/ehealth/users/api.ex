defmodule EHealth.Users.API do
  @moduledoc """
  API to work with platform users.
  """
  import Ecto.{Query, Changeset}, warn: false
  alias Ecto.Changeset
  alias EHealth.Users.CredentialsRecoveryRequest
  alias EView.Changeset.Validators.Email, as: EmailValidator
  alias EHealth.API.Mithril
  alias EHealth.Repo

  def create_credentials_recovery_request(attrs, opts \\ []) do
    upstream_headers = Keyword.get(opts, :upstream_headers, [])

    with {:ok, email} <- Map.fetch(attrs, "email"),
         {:ok, %{"data" => users}} <- Mithril.search_user(%{"email" => email}, upstream_headers),
         [%{"id" => user_id, "email" => user_email}] <- users,
         {:ok, request} <- insert_credentials_recovery_request(user_id),
         :ok <- send_email(user_email, request) do
      {:ok, %{request | expires_at: get_expiration_date(request)}}
    else
      :error ->
        changeset =
          %CredentialsRecoveryRequest{}
          |> change(%{})
          |> add_error(:email, "is not set", validation: :required)
          |> EmailValidator.validate_email(:email)

        {:error, changeset}

      [] ->
        changeset =
          %CredentialsRecoveryRequest{}
          |> change(%{})
          |> add_error(:email, "does not exist", validation: :existence)
          |> EmailValidator.validate_email(:email)

        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp insert_credentials_recovery_request(user_id) do
    %CredentialsRecoveryRequest{user_id: user_id}
    |> credentials_recovery_request_changeset(%{"user_id" => user_id})
    |> Repo.insert()
  end

  defp fetch_credentials_recovery_request(request_id) do
    case Repo.get(CredentialsRecoveryRequest, request_id) do
      nil ->
        :error

      %CredentialsRecoveryRequest{} = request ->
        {:ok, request}
    end
  end

  defp deactivate_credentials_recovery_request(request) do
    request
    |> credentials_recovery_request_changeset(%{"is_active" => false})
    |> Repo.update()
  end

  defp get_expiration_date(request) do
    ttl = Confex.get(:ehealth, :credentials_recovery_request_ttl)
    NaiveDateTime.add(request.inserted_at, ttl)
  end

  def reset_password(request_id, attrs, opts \\ []) do
    upstream_headers = Keyword.get(opts, :upstream_headers, [])
    with {:ok, %{user_id: user_id} = request} <- fetch_credentials_recovery_request(request_id),
         %Changeset{valid?: true} <- reset_password_changeset(attrs),
         {:ok, %{"data" => user}} <- Mithril.change_user(user_id, attrs, upstream_headers),
         {:ok, _updated_request} <- deactivate_credentials_recovery_request(request) do
      {:ok, user}
    else
      {:ok, %{"error" => error}} -> {:error, error}
      :error -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      %Changeset{} = changeset -> {:error, changeset}
    end
  end

  defp credentials_recovery_request_changeset(%CredentialsRecoveryRequest{} = request, attrs) do
    request
    |> cast(attrs, [:user_id, :is_active])
    |> validate_required([:user_id, :is_active])
  end

  defp reset_password_changeset(attrs) do
    types = %{password: :string}
    keys = Map.keys(types)

    {attrs, types}
    |> cast(attrs, keys)
    |> validate_required(keys)
  end

  defp send_email(email, %CredentialsRecoveryRequest{} = request) do
    case EHealth.Man.Templates.CredentialsRecoveryRequest.render(request) do
      {:ok, body} ->
        EHealth.Bamboo.Emails.CredentialsRecoveryRequest.send(email, body)
        :ok
      {:error, reason} -> {:error, reason}
    end
  end
end