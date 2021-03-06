defmodule EHealth.Declarations.API do
  @moduledoc false

  import Ecto.Changeset
  import EHealth.Utils.Connection, only: [get_client_id: 1, get_consumer_id: 1]
  import EHealth.Plugs.ClientContext, only: [get_context_params: 2]
  import EHealth.Utils.TypesConverter, only: [strings_to_keys: 1]

  alias EHealth.Validators.Preload
  alias EHealth.API.MediaStorage
  alias EHealth.{LegalEntities, Employees, Persons, Divisions}
  alias EHealth.Employees.Employee
  alias EHealth.Divisions.Division
  alias EHealth.LegalEntities.LegalEntity
  alias Scrivener.Page
  require Logger

  @mithril_api Application.get_env(:ehealth, :api_resolvers)[:mithril]
  @mpi_api Application.get_env(:ehealth, :api_resolvers)[:mpi]
  @ops_api Application.get_env(:ehealth, :api_resolvers)[:ops]
  @media_storage_api Application.get_env(:ehealth, :api_resolvers)[:media_storage]
  @signature_api Application.get_env(:ehealth, :api_resolvers)[:digital_signature]

  def get_person_declarations(%{} = params, headers) do
    with {:ok, person} <- Persons.get_person(headers),
         declaration_params <- Map.merge(params, %{"person_id" => person["id"]}),
         {:ok, %{"data" => declarations, "paging" => paging}} <- @ops_api.get_declarations(declaration_params, headers),
         references <- load_declarations_references(declarations),
         paging <- strings_to_keys(paging) do
      {:ok, %{declarations: declarations, declaration_references: references, person: person, paging: paging}}
    end
  end

  defp load_declarations_references(declarations) when is_list(declarations) do
    Preload.preload_references_for_list(declarations, [
      {"employee_id", :employee},
      {"division_id", :division},
      {"legal_entity_id", :legal_entity}
    ])
  end

  def get_declarations(params, headers) do
    with {:ok, %{"data" => declarations_data, "paging" => paging}} <- @ops_api.get_declarations(params, headers),
         related_ids <- fetch_related_ids(declarations_data),
         divisions <- Divisions.get_by_ids(related_ids["division_ids"]),
         employees <- Employees.get_by_ids(related_ids["employee_ids"]),
         legal_entities <- LegalEntities.get_by_ids(related_ids["legal_entity_ids"]),
         {:ok, persons} <-
           preload_persons(Enum.join(related_ids["person_ids"], ","), Map.get(params, "page_size"), headers),
         relations <- build_indexes(divisions, employees, legal_entities, persons["data"]),
         declarations <- merge_related_data(declarations_data, relations) do
      {:ok,
       %{
         declarations: declarations,
         paging: struct(Page, Enum.into(paging, %{}, fn {k, v} -> {String.to_atom(k), v} end))
       }}
    end
  end

  def get_declaration(id, headers) do
    user_id = get_consumer_id(headers)

    with {:ok, %{"data" => declaration_data}} <- @ops_api.get_declaration_by_id(id, headers),
         division = Divisions.get_by_id(declaration_data["division_id"]),
         employee = Employees.get_by_id(declaration_data["employee_id"]),
         legal_entity = LegalEntities.get_by_id(declaration_data["legal_entity_id"]),
         {:ok, %{"data" => person_data}} <- @mpi_api.person(declaration_data["person_id"], headers),
         merged_declaration_data = merge_related_data(declaration_data, person_data, legal_entity, division, employee),
         {:ok, %{"data" => user}} <- @mithril_api.get_user_by_id(user_id, headers),
         {:person_id, true} <- {:person_id, user["person_id"] == declaration_data["person_id"]},
         data = put_signed_content(merged_declaration_data, headers) do
      {:ok, data}
    else
      {:person_id, false} -> {:error, :forbidden}
      error -> error
    end
  end

  def fetch_related_ids(declarations) do
    acc = %{"person_ids" => [], "division_ids" => [], "employee_ids" => [], "legal_entity_ids" => []}

    declarations
    |> Enum.map_reduce(acc, fn declaration, acc ->
      acc =
        Enum.map(acc, fn {field_name, list} ->
          {field_name, put_related_id(list, declaration[String.trim_trailing(field_name, "s")])}
        end)

      {nil, acc}
    end)
    |> elem(1)
    |> Enum.into(%{})
  end

  defp preload_persons("", _, _), do: {:ok, %{"data" => []}}
  defp preload_persons(ids, nil, headers), do: @mpi_api.search(%{ids: ids}, headers)
  defp preload_persons(ids, page_size, headers), do: @mpi_api.search(%{ids: ids, page_size: page_size}, headers)

  defp put_related_id(list, id) do
    case Enum.member?(list, id) do
      false -> List.insert_at(list, 0, id)
      true -> list
    end
  end

  def build_indexes(divisions, employees, legal_entities, persons) do
    %{}
    |> Map.put(:persons, build_index(persons))
    |> Map.put(:divisions, build_index(divisions))
    |> Map.put(:employees, build_index(employees))
    |> Map.put(:legal_entities, build_index(legal_entities))
  end

  def build_index([]), do: %{}

  def build_index(data) do
    data
    |> Enum.map_reduce(%{}, fn
      %Division{} = item, acc ->
        {nil, Map.put(acc, item.id, item)}

      %LegalEntity{} = item, acc ->
        {nil, Map.put(acc, item.id, item)}

      %Employee{} = item, acc ->
        {nil, Map.put(acc, item.id, item)}

      item, acc ->
        {nil, Map.put(acc, item["id"], item)}
    end)
    |> elem(1)
  end

  def merge_related_data(data, relations) do
    Enum.map(data, fn item ->
      merge_related_data(
        item,
        Map.get(relations.persons, item["person_id"]),
        Map.get(relations.legal_entities, item["legal_entity_id"]),
        Map.get(relations.divisions, item["division_id"]),
        Map.get(relations.employees, item["employee_id"])
      )
    end)
  end

  def merge_related_data(declaration, person, legal_entity, division, employee) do
    declaration
    |> Map.merge(%{
      "person" => person,
      "division" => division,
      "employee" => employee,
      "legal_entity" => legal_entity
    })
    |> Map.drop(~W(person_id division_id employee_id legal_entity_id))
  end

  defp put_signed_content(declaration_data, headers) do
    with id <- Map.get(declaration_data, "id"),
         {:ok, %{"data" => data}} <-
           @media_storage_api.create_signed_url(
             "GET",
             MediaStorage.config()[:declaration_bucket],
             "signed_content",
             id,
             headers
           ),
         {:ok, secret_url} <- Map.fetch(data, "secret_url"),
         {:ok, %{body: signed_content}} <- @media_storage_api.get_signed_content(secret_url),
         {:ok, %{"data" => %{"content" => content}}} <-
           @signature_api.decode_and_validate(Base.encode64(signed_content), "base64", headers) do
      Map.put(declaration_data, "content", Map.get(content, "content"))
    end
  end

  def get_declaration_by_id(id, headers) do
    with {:ok, %{"data" => response_data}} <- @ops_api.get_declaration_by_id(id, headers),
         {:ok, declaration_data} <- expand_declaration_relations(response_data, headers),
         do: {:ok, declaration_data}
  end

  def update_declaration(id, attrs, headers) do
    with {:ok, %{"data" => declaration}} <- @ops_api.get_declaration_by_id(id, headers),
         :ok <- check_declaration_access(declaration["legal_entity_id"], headers),
         :ok <- active?(declaration) do
      @ops_api.update_declaration(declaration["id"], %{"declaration" => attrs}, headers)
    end
  end

  def terminate(id, user_id, params, headers) do
    with {:ok, %{"data" => user}} <- @mithril_api.get_user_by_id(user_id, headers),
         {:ok, declaration} <- get_declaration_by_id(id, headers),
         {:status, true} <- {:status, declaration["status"] == "active"},
         {:person_id, true} <- {:person_id, user["person_id"] == get_in(declaration, ~w(person id))},
         params <-
           params
           |> Map.take(["reason_description"])
           |> Map.put("updated_by", user_id)
           |> Map.put("reason", "manual_person"),
         {:ok, %{"data" => declaration}} <- @ops_api.terminate_declaration(id, params, headers),
         {:ok, declaration_data} <- expand_declaration_relations(declaration, headers) do
      {:ok, declaration_data}
    else
      {:status, false} -> {:conflict, "Declaration is not active"}
      {:person_id, false} -> {:error, :forbidden}
      error -> error
    end
  end

  def terminate_declarations(attrs, headers) do
    user_id = get_consumer_id(headers)
    types = %{person_id: Ecto.UUID, employee_id: Ecto.UUID, reason_description: :string}

    {%{}, types}
    |> cast(attrs, Map.keys(types))
    |> validate_required_one_inclusion([:person_id, :employee_id])
    |> terminate_ops_declarations(user_id, attrs["reason_description"], headers)
  end

  defp terminate_ops_declarations(%Ecto.Changeset{valid?: false} = changeset, _, _, _), do: changeset

  defp terminate_ops_declarations(%Ecto.Changeset{changes: %{person_id: person_id}}, user_id, reason_desc, headers) do
    person_id
    |> @ops_api.terminate_person_declarations(user_id, "manual_person", reason_desc, headers)
    |> maybe_render_error("Person does not have active declarations")
  end

  defp terminate_ops_declarations(%Ecto.Changeset{changes: %{employee_id: employee_id}}, user_id, reason_desc, headers) do
    employee_id
    |> @ops_api.terminate_employee_declarations(user_id, "manual_employee", reason_desc, headers)
    |> maybe_render_error("Employee does not have active declarations")
  end

  defp maybe_render_error({:ok, %{"data" => %{"terminated_declarations" => []}}}, message) do
    {:error, {:"422", message}}
  end

  defp maybe_render_error(response, _message), do: response

  defp validate_required_one_inclusion(%{changes: changes} = changeset, fields) do
    case map_size(Map.take(changes, fields)) do
      1 ->
        changeset

      _ ->
        add_error(
          changeset,
          hd(fields),
          "One and only one of these fields must be present: " <> Enum.join(fields, ", ")
        )
    end
  end

  def expand_declaration_relations(%{"legal_entity_id" => legal_entity_id} = declaration, headers) do
    with :ok <- check_declaration_access(legal_entity_id, headers) do
      person = load_relation(@mpi_api, :person, declaration["person_id"], headers)
      legal_entity = LegalEntities.get_by_id(legal_entity_id)
      division = Divisions.get_by_id(declaration["division_id"])
      employee = Employees.get_by_id(declaration["employee_id"])
      declaration_data = merge_related_data(declaration, person, legal_entity, division, employee)

      {:ok, declaration_data}
    end
  end

  defp check_declaration_access(legal_entity_id, headers) do
    case @mithril_api.get_client_type_name(get_client_id(headers), headers) do
      {:ok, nil} ->
        {:error, :access_denied}

      {:ok, client_type} ->
        headers
        |> get_client_id()
        |> get_context_params(client_type)
        |> legal_entity_allowed?(legal_entity_id)

      err ->
        err
    end
  end

  def load_relation(module, func, id, headers) do
    case apply(module, func, [id, headers]) do
      {:ok, %{"data" => entity}} -> entity
      _ -> %{}
    end
  end

  def legal_entity_allowed?(%{"legal_entity_id" => id}, legal_entity_id) when legal_entity_id != id do
    {:error, :forbidden}
  end

  def legal_entity_allowed?(_, _), do: :ok

  defp active?(%{"is_active" => true}), do: :ok
  defp active?(%{"is_active" => false}), do: {:error, :not_found}
end
