# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Import.Runner.Gravity.BridgeDeposits do
  @moduledoc """
  Bulk imports `t:Explorer.Chain.Gravity.BridgeDeposit.t/0`.
  """

  alias Ecto.{Changeset, Multi, Repo}
  alias Explorer.Chain.Gravity.BridgeDeposit
  alias Explorer.Chain.Import
  alias Explorer.Prometheus.Instrumenter

  @behaviour Import.Runner

  # milliseconds
  @timeout 60_000

  @type imported :: [BridgeDeposit.t()]

  @impl Import.Runner
  def ecto_schema_module, do: BridgeDeposit

  @impl Import.Runner
  def option_key, do: :gravity_bridge_deposits

  @impl Import.Runner
  def imported_table_row do
    %{
      value_type: "[#{ecto_schema_module()}.t()]",
      value_description: "List of `t:#{ecto_schema_module()}.t/0`s"
    }
  end

  @impl Import.Runner
  def run(multi, changes_list, %{timestamps: timestamps} = options) do
    insert_options =
      options
      |> Map.get(option_key(), %{})
      |> Map.take(~w(on_conflict timeout)a)
      |> Map.put_new(:timeout, @timeout)
      |> Map.put(:timestamps, timestamps)

    Multi.run(multi, :insert_gravity_bridge_deposits, fn repo, _ ->
      Instrumenter.block_import_stage_runner(
        fn -> insert(repo, changes_list, insert_options) end,
        :block_referencing,
        :gravity_bridge_deposits,
        :gravity_bridge_deposits
      )
    end)
  end

  @impl Import.Runner
  def timeout, do: @timeout

  @spec insert(Repo.t(), [map()], %{required(:timeout) => timeout(), required(:timestamps) => Import.timestamps()}) ::
          {:ok, [BridgeDeposit.t()]} | {:error, [Changeset.t()]}
  def insert(repo, changes_list, %{timeout: timeout, timestamps: timestamps} = options) when is_list(changes_list) do
    # A deposit is fully determined by its log, so a row that already exists never needs an update.
    on_conflict = Map.get(options, :on_conflict, :nothing)

    # Enforce BridgeDeposit ShareLocks order (see docs: sharelock.md)
    ordered_changes_list = Enum.sort_by(changes_list, &{&1.block_hash, &1.log_index})

    Import.insert_changes_list(
      repo,
      ordered_changes_list,
      conflict_target: [:block_hash, :log_index],
      on_conflict: on_conflict,
      for: BridgeDeposit,
      returning: true,
      timeout: timeout,
      timestamps: timestamps
    )
  end
end
