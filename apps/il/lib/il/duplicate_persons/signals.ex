defmodule Il.DuplicatePersons.Signals do
  @moduledoc false

  use GenServer

  alias Il.API.MPI
  alias Il.DuplicatePersons.Cleanup
  alias Il.DuplicatePersons.CleanupTasks
  alias Il.Declarations.Person

  def start_link do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  def deactivate do
    GenServer.call(__MODULE__, :deactivate)
  end

  def handle_call(:deactivate, _from, state) do
    {:ok, %{"data" => merge_candidates}} = MPI.get_merge_candidates(%{status: Person.status(:new)})

    groups =
      Enum.group_by merge_candidates, &(&1["master_person_id"]), &({&1["id"], &1["person_id"]})

    cleanup_task = fn {master_person_id, duplicate_person_ids} ->
      Cleanup.update_master_merged_ids(master_person_id, Enum.map(duplicate_person_ids, &(elem(&1, 1))))

      Enum.each duplicate_person_ids, fn {merge_candidate_id, person_id} ->
        Cleanup.cleanup(merge_candidate_id, person_id)
      end
    end

    Enum.each groups, fn group ->
      Task.Supervisor.start_child(CleanupTasks, fn -> cleanup_task.(group) end)
    end

    {:reply, :ok, state}
  end
end
