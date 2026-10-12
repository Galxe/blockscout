# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Indexer.Transform.Gravity.BridgeDepositsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog, only: [capture_log: 1]

  alias Indexer.Transform.Gravity.BridgeDeposits

  @contract "0x595475934ed7d9faa7fca28341c2ce583904a44e"
  @event "0x28a48d0161bbc70613fb99402d1437dea020d82e4495b003eb642c78fa4e2584"

  setup do
    initial = Application.get_env(:indexer, BridgeDeposits)
    Application.put_env(:indexer, BridgeDeposits, contract_address: @contract)
    on_exit(fn -> Application.put_env(:indexer, BridgeDeposits, initial) end)
  end

  # Log 3 of mainnet transaction 0x57d53ae6…db23 in block 44675449:
  # 50,000 G credited to 0x15918ff7…cc44, bridge message nonce 0x867.
  defp mainnet_log(overrides \\ %{}) do
    Map.merge(
      %{
        address_hash: @contract,
        block_hash: "0x99dc8e97d7d7c676cd5fb566da454620f2dcf95b34ab5ff7d9e38c8482088b17",
        block_number: 44_675_449,
        transaction_hash: "0x57d53ae6fe9eb1b00b3adcfb8562bff2d29750eb0eea2f33c4b0dbcef89ddb23",
        transaction_index: 0,
        index: 3,
        first_topic: @event,
        second_topic: "0x00000000000000000000000015918ff7f6c44592c81d999b442956b07d26cc44",
        third_topic: "0x0000000000000000000000000000000000000000000000000000000000000867",
        fourth_topic: nil,
        data: "0x000000000000000000000000000000000000000000000a968163f0a57b400000"
      },
      overrides
    )
  end

  test "decodes the mainnet NativeMinted log" do
    assert BridgeDeposits.parse([mainnet_log()]) == [
             %{
               block_hash: "0x99dc8e97d7d7c676cd5fb566da454620f2dcf95b34ab5ff7d9e38c8482088b17",
               block_number: 44_675_449,
               transaction_hash: "0x57d53ae6fe9eb1b00b3adcfb8562bff2d29750eb0eea2f33c4b0dbcef89ddb23",
               log_index: 3,
               recipient_address_hash: "0x15918ff7f6c44592c81d999b442956b07d26cc44",
               amount: 50_000 * 10 ** 18,
               nonce: 0x867
             }
           ]
  end

  test "returns no deposits for no logs" do
    assert BridgeDeposits.parse([]) == []
  end

  test "ignores NativeMinted logs of other contracts" do
    assert BridgeDeposits.parse([mainnet_log(%{address_hash: "0x0000000000000000000000000000000000000001"})]) == []
  end

  test "ignores other events of the bridge contract" do
    other_event = "0x" <> String.duplicate("ab", 32)
    assert BridgeDeposits.parse([mainnet_log(%{first_topic: other_event})]) == []
  end

  test "ignores logs without topics" do
    assert BridgeDeposits.parse([mainnet_log(%{first_topic: nil, second_topic: nil, third_topic: nil})]) == []
  end

  test "matches the contract and the event regardless of letter case" do
    Application.put_env(:indexer, BridgeDeposits, contract_address: "0x595475934ED7D9FAA7FCA28341C2CE583904A44E")

    log =
      mainnet_log(%{
        address_hash: "0x595475934Ed7d9fAa7fCa28341C2ce583904A44e",
        first_topic: @event |> String.upcase() |> String.replace_prefix("0X", "0x"),
        second_topic: "0x00000000000000000000000015918FF7F6C44592C81D999B442956B07D26CC44"
      })

    assert [%{recipient_address_hash: "0x15918ff7f6c44592c81d999b442956b07d26cc44"}] = BridgeDeposits.parse([log])
  end

  describe "a log that does not match the event ABI" do
    for {name, overrides} <- [
          {"recipient topic with non-zero padding",
           %{second_topic: "0x01000000000000000000000015918ff7f6c44592c81d999b442956b07d26cc44"}},
          {"nonce above uint128", %{third_topic: "0x0000000000000000000000000000000100000000000000000000000000000000"}},
          {"data longer than one word", %{data: "0x" <> String.duplicate("00", 64)}},
          {"empty data", %{data: "0x"}},
          {"missing nonce topic", %{third_topic: nil}}
        ] do
      test "is skipped and logged: #{name}" do
        log = mainnet_log(unquote(Macro.escape(overrides)))

        message = capture_log(fn -> assert BridgeDeposits.parse([log]) == [] end)

        assert message =~ "Skipping malformed Gravity NativeMinted log"
        assert message =~ "block 44675449"
        assert message =~ "log index 3"
      end
    end

    test "does not stop the other deposits of the batch" do
      good_before = mainnet_log(%{index: 1})
      bad = mainnet_log(%{index: 2, data: "0x"})
      good_after = mainnet_log(%{index: 4})

      capture_log(fn ->
        assert [%{log_index: 1}, %{log_index: 4}] = BridgeDeposits.parse([good_before, bad, good_after])
      end)
    end
  end
end
