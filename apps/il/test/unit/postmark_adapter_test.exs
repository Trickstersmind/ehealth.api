defmodule Il.Unit.PostmarkAdapterTest do
  @moduledoc false

  use ExUnit.Case

  alias Il.Bamboo.PostmarkAdapter

  test "handle_config" do
    System.put_env("POSTMARK_API_KEY", "111")
    assert %{adapter: Bamboo.TestAdapter, api_key: "111"} == PostmarkAdapter.handle_config(%{})
  end
end
