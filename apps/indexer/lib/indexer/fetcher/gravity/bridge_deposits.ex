# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Indexer.Fetcher.Gravity.BridgeDeposits do
  @moduledoc """
  Turns NativeMinted events of the Gravity bridge receiver into
  `Explorer.Chain.Gravity.BridgeDeposit` rows and coin balance fetches.

  Bridge credits are written by the mint precompile without a value transfer,
  so block import never marks the recipient as involved in the block. Each
  tick takes bridge logs that have no deposit row yet; the same code path
  backfills already indexed blocks and follows new ones.
  """

  use GenServer
  use Indexer.Fetcher

  require Logger

  alias Explorer.Chain
  alias Explorer.Chain.Gravity.BridgeDeposit
  alias Explorer.Chain.Hash
  alias Indexer.Fetcher.CoinBalance.Realtime, as: CoinBalanceRealtime
  alias Indexer.Transform.Gravity.BridgeDeposits, as: BridgeDepositsTransform

  @interval :timer.seconds(5)
  @batch_size 500

  @enforce_keys [:contract_address_hash]
  defstruct [:contract_address_hash, :json_rpc_named_arguments, interval: @interval, batch_size: @batch_size]

  @type t :: %__MODULE__{
          contract_address_hash: Hash.Address.t(),
          json_rpc_named_arguments: EthereumJSONRPC.json_rpc_named_arguments() | nil,
          interval: non_neg_integer(),
          batch_size: pos_integer()
        }

  def start_link([init_opts, server_opts]) do
    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @impl GenServer
  def init(init_opts) do
    Logger.metadata(fetcher: :gravity_bridge_deposits)

    contract_address = Application.get_env(:indexer, __MODULE__)[:contract_address]

    contract_address_hash =
      case Hash.Address.cast(contract_address) do
        {:ok, contract_address_hash} ->
          contract_address_hash

        :error ->
          raise ArgumentError,
                "INDEXER_GRAVITY_BRIDGE_CONTRACT must be an address, got: #{inspect(contract_address)}"
      end

    {:ok,
     %__MODULE__{
       contract_address_hash: contract_address_hash,
       json_rpc_named_arguments: init_opts[:json_rpc_named_arguments]
     }, {:continue, :check_contract_code}}
  end

  # A well-formed but wrong address (e.g. the mainnet default on a testnet)
  # would index nothing without any error, so an address without code is
  # reported and the fetcher stays idle.
  @impl GenServer
  def handle_continue(:check_contract_code, %__MODULE__{contract_address_hash: contract_address_hash} = state) do
    address = to_string(contract_address_hash)

    case EthereumJSONRPC.fetch_codes([%{block_quantity: "latest", address: address}], state.json_rpc_named_arguments) do
      {:ok, %{params_list: [%{code: "0x"}]}} ->
        Logger.error(
          "No contract code at the Gravity bridge receiver #{address}; check INDEXER_GRAVITY_BRIDGE_CONTRACT. " <>
            "Bridge deposits will not be indexed."
        )

      {:ok, %{params_list: [_]}} ->
        send(self(), :process_logs)

      # The node being briefly unavailable must not stop indexing for good.
      other ->
        Logger.warning("Could not check the Gravity bridge receiver code at #{address}: #{inspect(other)}")
        send(self(), :process_logs)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:process_logs, %__MODULE__{interval: interval, batch_size: batch_size} = state) do
    delay =
      case process_batch(state) do
        # A full batch means more logs are waiting, e.g. during the initial backfill.
        {:ok, ^batch_size} ->
          0

        {:ok, _logs_taken} ->
          interval

        {:error, reason} ->
          Logger.error("Failed to process Gravity bridge deposits: #{inspect(reason)}")
          interval
      end

    Process.send_after(self(), :process_logs, delay)

    {:noreply, state}
  end

  @doc """
  Imports deposits for up to `batch_size` unprocessed bridge logs and queues
  the coin balance fetches at their blocks. Returns the number of logs taken.
  """
  @spec process_batch(t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def process_batch(%__MODULE__{contract_address_hash: contract_address_hash, batch_size: batch_size}) do
    logs = BridgeDeposit.unprocessed_logs(contract_address_hash, batch_size)

    with {:ok, deposits} <- BridgeDepositsTransform.parse(logs),
         {:ok, imported} <- import_deposits(deposits) do
      CoinBalanceRealtime.async_fetch_balances(Map.get(imported, :address_coin_balances, []))
      {:ok, length(logs)}
    end
  rescue
    exception in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, exception}
  end

  defp import_deposits([]), do: {:ok, %{}}

  defp import_deposits(deposits) do
    # One system transaction can credit the same recipient several times in a block,
    # and the coin balance runner cannot upsert the same row twice in one statement.
    coin_balances_params =
      deposits
      |> Enum.map(&%{address_hash: &1.recipient_address_hash, block_number: &1.block_number})
      |> Enum.uniq()

    addresses_params =
      deposits
      |> Enum.map(&%{hash: &1.recipient_address_hash})
      |> Enum.uniq()

    case Chain.import(%{
           addresses: %{params: addresses_params},
           address_coin_balances: %{params: coin_balances_params},
           gravity_bridge_deposits: %{params: deposits}
         }) do
      {:ok, imported} -> {:ok, imported}
      {:error, step, reason, _changes_so_far} -> {:error, {step, reason}}
      {:error, _} = error -> error
    end
  end
end
