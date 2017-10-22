defmodule Il.Web.INNMController do
  @moduledoc false
  use Il.Web, :controller

  alias Scrivener.Page
  alias Il.PRM.Medications.API
  alias Il.PRM.Medications.INNM.Schema, as: INNM

  action_fallback Il.Web.FallbackController

  def index(conn, params) do
    with %Page{} = paging <- API.list_innms(params) do
      render(conn, "index.json", innms: paging.entries, paging: paging)
    end
  end

  def create(conn, innm_params) do
    with {:ok, %INNM{} = innm} <- API.create_innm(innm_params, conn.req_headers) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", innm_path(conn, :show, innm))
      |> render("show.json", innm: innm)
    end
  end

  def show(conn, %{"id" => id}) do
    innm = API.get_innm!(id)
    render(conn, "show.json", innm: innm)
  end
end
