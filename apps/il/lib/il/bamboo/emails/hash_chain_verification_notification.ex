defmodule Il.Bamboo.Emails.HashChainVeriricationNotification do
  @moduledoc false

  use Confex, otp_app: :il
  import Bamboo.Email

  def new(body) do
    new_email(
      from: config()[:from],
      to: config()[:to],
      subject: config()[:subject],
      html_body: body
    )
  end
end
