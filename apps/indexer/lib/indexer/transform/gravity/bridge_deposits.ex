# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Indexer.Transform.Gravity.BridgeDeposits do
  @moduledoc """
  Extracts `Explorer.Chain.Gravity.BridgeDeposit` params from the logs of the
  blocks being imported: the Gravity bridge receiver's
  `NativeMinted(address indexed recipient, uint256 amount, uint128 indexed nonce)`
  events.

  Bridge credits are written by the mint precompile without a value transfer,
  so these events are the only trace of them in a block.
  """

  require Logger

  alias Explorer.Chain.Gravity.BridgeDeposit

  @uint128_max 2 ** 128 - 1

  @doc """
  Returns deposit params for the bridge receiver's NativeMinted logs among the
  given log import params.

  The event ABI fixes the layout, so a log that does not decode means the
  contract changed. Such a log is reported and skipped: failing the import
  instead would stop the indexer at that block.
  """
  @spec parse([map()]) :: [map()]
  def parse(logs) do
    contract_address = String.downcase(Application.get_env(:indexer, __MODULE__)[:contract_address])
    event_signature = BridgeDeposit.event_signature()

    logs
    |> Enum.filter(&bridge_log?(&1, contract_address, event_signature))
    |> Enum.flat_map(&decode_or_skip/1)
  end

  defp bridge_log?(%{address_hash: address_hash, first_topic: first_topic}, contract_address, event_signature)
       when is_binary(address_hash) and is_binary(first_topic) do
    String.downcase(address_hash) == contract_address and String.downcase(first_topic) == event_signature
  end

  defp bridge_log?(_log, _contract_address, _event_signature), do: false

  defp decode_or_skip(log) do
    case decode(log) do
      {:ok, deposit} ->
        [deposit]

      :error ->
        Logger.error(
          "Skipping malformed Gravity NativeMinted log: block #{log.block_number}, " <>
            "log index #{log.index}, transaction #{log.transaction_hash}"
        )

        []
    end
  end

  defp decode(%{second_topic: "0x" <> recipient_topic, third_topic: "0x" <> nonce_topic, data: "0x" <> data} = log) do
    with {:ok, <<0::size(96), recipient::binary-size(20)>>} <- Base.decode16(recipient_topic, case: :mixed),
         {:ok, <<nonce::unsigned-big-integer-size(256)>>} when nonce <= @uint128_max <-
           Base.decode16(nonce_topic, case: :mixed),
         {:ok, <<amount::unsigned-big-integer-size(256)>>} <- Base.decode16(data, case: :mixed) do
      {:ok,
       %{
         block_hash: log.block_hash,
         block_number: log.block_number,
         transaction_hash: log.transaction_hash,
         log_index: log.index,
         recipient_address_hash: "0x" <> Base.encode16(recipient, case: :lower),
         amount: amount,
         nonce: nonce
       }}
    else
      _ -> :error
    end
  end

  defp decode(_log), do: :error
end
