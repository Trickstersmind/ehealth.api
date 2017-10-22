defmodule Il.API.OTPVerification do
  @moduledoc """
  OTP Verification API client
  """

  use HTTPoison.Base
  use Confex, otp_app: :il
  use Il.API.HeadersProcessor
  use Il.API.Helpers.MicroserviceBase

  def initialize(number, headers \\ []) do
    post!("/verifications", Poison.encode!(%{phone_number: number}), headers)
  end

  def search(number, headers \\ []) do
    get!("/verifications/#{number}", headers)
  end

  def complete(number, params, headers \\ []) do
    patch!("/verifications/#{number}/actions/complete", Poison.encode!(params), headers)
  end
end
