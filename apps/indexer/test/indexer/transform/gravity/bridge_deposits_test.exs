# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Indexer.Transform.Gravity.BridgeDepositsTest do
  use ExUnit.Case, async: true

  alias Explorer.Chain.{Data, Hash}
  alias Indexer.Transform.Gravity.BridgeDeposits

  # Log 3 of mainnet transaction 0x57d53ae6…db23 in block 44675449:
  # 50,000 G credited to 0x15918ff7…cc44, bridge message nonce 0x867.
  defp mainnet_log(overrides \\ %{}) do
    {:ok, block_hash} = Hash.Full.cast("0x99dc8e97d7d7c676cd5fb566da454620f2dcf95b34ab5ff7d9e38c8482088b17")
    {:ok, transaction_hash} = Hash.Full.cast("0x57d53ae6fe9eb1b00b3adcfb8562bff2d29750eb0eea2f33c4b0dbcef89ddb23")
    {:ok, second_topic} = Hash.Full.cast("0x00000000000000000000000015918ff7f6c44592c81d999b442956b07d26cc44")
    {:ok, third_topic} = Hash.Full.cast("0x0000000000000000000000000000000000000000000000000000000000000867")
    {:ok, data} = Data.cast("0x000000000000000000000000000000000000000000000a968163f0a57b400000")

    Map.merge(
      %{
        block_hash: block_hash,
        block_number: 44_675_449,
        transaction_hash: transaction_hash,
        index: 3,
        second_topic: second_topic,
        third_topic: third_topic,
        data: data
      },
      overrides
    )
  end

  test "decodes the mainnet NativeMinted log" do
    log = mainnet_log()
    {:ok, recipient} = Hash.Address.cast("0x15918ff7f6c44592c81d999b442956b07d26cc44")

    assert {:ok, [deposit]} = BridgeDeposits.parse([log])

    assert deposit == %{
             block_hash: log.block_hash,
             block_number: 44_675_449,
             transaction_hash: log.transaction_hash,
             log_index: 3,
             recipient_address_hash: recipient,
             amount: 50_000 * 10 ** 18,
             nonce: 0x867
           }
  end

  test "returns no deposits for no logs" do
    assert {:ok, []} = BridgeDeposits.parse([])
  end

  test "rejects a recipient topic with non-zero padding" do
    {:ok, bad_topic} = Hash.Full.cast("0x00000000000000000000000115918ff7f6c44592c81d999b442956b07d26cc44")
    log = mainnet_log(%{second_topic: bad_topic})

    assert {:error, {:malformed_log, ^log}} = BridgeDeposits.parse([mainnet_log(), log])
  end

  test "rejects a nonce that does not fit uint128" do
    {:ok, big_nonce} = Hash.Full.cast("0x0000000000000000000000000000000100000000000000000000000000000000")
    log = mainnet_log(%{third_topic: big_nonce})

    assert {:error, {:malformed_log, ^log}} = BridgeDeposits.parse([log])
  end

  test "rejects data that is not a single uint256" do
    {:ok, short_data} = Data.cast("0x0a968163f0a57b400000")
    log = mainnet_log(%{data: short_data})

    assert {:error, {:malformed_log, ^log}} = BridgeDeposits.parse([log])
  end

  test "rejects a log without topics" do
    log = mainnet_log(%{second_topic: nil})

    assert {:error, {:malformed_log, ^log}} = BridgeDeposits.parse([log])
  end
end
