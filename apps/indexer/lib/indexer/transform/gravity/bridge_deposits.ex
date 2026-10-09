# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Indexer.Transform.Gravity.BridgeDeposits do
  @moduledoc """
  Decodes `NativeMinted(address indexed recipient, uint256 amount, uint128 indexed nonce)`
  logs of the Gravity bridge receiver into `Explorer.Chain.Gravity.BridgeDeposit` params.
  """

  alias Explorer.Chain.{Data, Hash}

  @uint128_max 2 ** 128 - 1

  @doc """
  Decodes all logs, or returns the first log that does not match the event ABI.

  The ABI fixes the layout, so a log that does not decode means the contract
  changed; the caller must surface it instead of skipping the credit.
  """
  @spec parse([map()]) :: {:ok, [map()]} | {:error, {:malformed_log, map()}}
  def parse(logs) do
    logs
    |> Enum.reduce_while([], fn log, acc ->
      case decode(log) do
        {:ok, deposit} -> {:cont, [deposit | acc]}
        :error -> {:halt, {:error, {:malformed_log, log}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      deposits -> {:ok, Enum.reverse(deposits)}
    end
  end

  defp decode(
         %{
           second_topic: %Hash{bytes: <<0::size(96), recipient_bytes::binary-size(20)>>},
           third_topic: %Hash{bytes: <<nonce::unsigned-big-integer-size(256)>>},
           data: %Data{bytes: <<amount::unsigned-big-integer-size(256)>>}
         } = log
       )
       when nonce <= @uint128_max do
    {:ok, recipient_address_hash} = Hash.Address.cast(recipient_bytes)

    {:ok,
     %{
       block_hash: log.block_hash,
       block_number: log.block_number,
       transaction_hash: log.transaction_hash,
       log_index: log.index,
       recipient_address_hash: recipient_address_hash,
       amount: amount,
       nonce: nonce
     }}
  end

  defp decode(_log), do: :error
end
