defmodule EHealth.Web.MedicationRequestRequestController do
  @moduledoc false
  use EHealth.Web, :controller

  alias EHealth.MedicationRequestRequests, as: API
  alias EHealth.MedicationRequestRequest
  alias Scrivener.Page

  action_fallback EHealth.Web.FallbackController

  def index(conn, params) do
    with %Page{} = paging <- API.list_medication_request_requests(params) do
      render(conn, "index.json", medication_request_requests: paging.entries, paging: paging)
    end
  end

  def create(conn, %{"medication_request_request" => params}) do
    user_id = get_consumer_id(conn.req_headers)
    client_id = get_client_id(conn.req_headers)

    with {:ok, %MedicationRequestRequest{} = medication_request_request} <-
          API.create(params, user_id, client_id) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", medication_request_request_path(conn, :show, medication_request_request))
      |> render("show.json", medication_request_request: medication_request_request)
    end
  end

  def prequalify(conn, params) do
    user_id = get_consumer_id(conn.req_headers)
    client_id = get_client_id(conn.req_headers)
    with {:ok, programs} <- API.prequalify(params, user_id, client_id) do
      conn
      |> put_status(200)
      |> render("show_prequalify_programs.json", %{programs: programs})
    end
  end

  def reject(conn, %{"id" => id}) do
    user_id = get_consumer_id(conn.req_headers)
    client_id = get_client_id(conn.req_headers)
    with {:ok, mrr} <- API.reject(id, user_id, client_id) do
      conn
      |> put_status(200)
      |> render("show.json", medication_request_request: mrr)
    end
  end

  def show(conn, %{"id" => id}) do
    medication_request_request = API.get_medication_request_request!(id)
    render(conn, "show.json", medication_request_request: medication_request_request)
  end
end
