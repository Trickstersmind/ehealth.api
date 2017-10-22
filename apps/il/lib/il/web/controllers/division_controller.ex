defmodule Il.Web.DivisionController do
  @moduledoc false

  use Il.Web, :controller

  alias Scrivener.Page
  alias Il.Divisions.API
  alias Il.PRM.Divisions.Schema, as: Division

  action_fallback Il.Web.FallbackController

  def index(%Plug.Conn{req_headers: req_headers} = conn, params) do
    with %Page{} = paging <- API.search(get_client_id(req_headers), params) do
      render(conn, "index.json", divisions: paging.entries, paging: paging)
    end
  end

  def create(%Plug.Conn{req_headers: req_headers} = conn, params) do
    with {:ok, division} <- API.create(params, req_headers) do
      conn
      |> put_status(:created)
      |> render("show.json", division: division)
    end
  end

  def show(%Plug.Conn{req_headers: req_headers} = conn, %{"id" => id}) do
    with {:ok, division} <- API.get_by_id(get_client_id(req_headers), id) do
      render(conn, "show.json", division: division)
    end
  end

  def update(%Plug.Conn{req_headers: headers} = conn, %{"id" => id} = division_params) do
    with {:ok, division} <- API.update(id, division_params, headers) do
      render(conn, "show.json", division: division)
    end
  end

  def activate(%Plug.Conn{req_headers: headers} = conn, %{"id" => id}) do
    with {:ok, division} <- API.update_status(id, Division.status(:active), headers) do
      render(conn, "show.json", division: division)
    end
  end

  def deactivate(%Plug.Conn{req_headers: headers} = conn, %{"id" => id}) do
    with {:ok, division} <- API.update_status(id, Division.status(:inactive), headers) do
      render(conn, "show.json", division: division)
    end
  end
end
