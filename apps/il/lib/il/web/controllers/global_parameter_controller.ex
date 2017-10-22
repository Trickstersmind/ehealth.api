defmodule Il.Web.GlobalParameterController do
  @moduledoc false

  use Il.Web, :controller

  alias Il.PRM.GlobalParameters

  action_fallback Il.Web.FallbackController

  def index(conn, _params) do
    with global_parameters <- GlobalParameters.list_global_parameters() do
      render(conn, "index.json", global_parameters: global_parameters)
    end
  end

  def create_or_update(%Plug.Conn{req_headers: req_headers} = conn, params) do
    client_id = get_client_id(req_headers)

    with {:ok, global_parameters} <- GlobalParameters.create_or_update_global_parameters(params, client_id) do
      render(conn, "index.json", global_parameters: global_parameters)
    end
  end
end
