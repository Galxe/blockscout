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
  defstruct [:contract_address_hash, interval: @interval, batch_size: @batch_size]

  @type t :: %__MODULE__{
          contract_address_hash: Hash.Address.t(),
          interval: non_neg_integer(),
          batch_size: pos_integer()
        }

  def start_link([init_opts, server_opts]) do
    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @impl GenServer
  def init(_init_opts) do
    Logger.metadata(fetcher: :gravity_bridge_deposits)

    # A wrong address would silently index nothing, so a misconfiguration stops the fetcher at start.
    {:ok, contract_address_hash} =
      Hash.Address.cast(Application.get_env(:indexer, __MODULE__)[:contract_address])

    Process.send_after(self(), :process_logs, @interval)

    {:ok, %__MODULE__{contract_address_hash: contract_address_hash}}
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
