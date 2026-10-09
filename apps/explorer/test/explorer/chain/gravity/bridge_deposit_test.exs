# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Gravity.BridgeDepositTest do
  use Explorer.DataCase
  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  alias Explorer.Chain.{Block, Hash, Transaction}
  alias Explorer.Chain.Gravity.BridgeDeposit

  @contract_address "0x595475934ed7d9faa7fca28341c2ce583904a44e"

  if @chain_type == :gravity do
    setup do
      contract = insert(:address, hash: @contract_address)
      {:ok, contract_address_hash} = Hash.Address.cast(@contract_address)
      %{contract: contract, contract_address_hash: contract_address_hash}
    end

    # The log's block fields must match its transaction: depending on the logs
    # migration state, logs join transactions by hash or by (block_number, transaction_index).
    defp insert_bridge_log(transaction, attrs) do
      insert(
        :gravity_bridge_deposit_log,
        Map.merge(
          %{transaction: transaction, block: transaction.block, block_number: transaction.block_number},
          Map.new(attrs)
        )
      )
    end

    describe "unprocessed_logs/2" do
      test "returns NativeMinted logs of the bridge contract only", %{contract: contract, contract_address_hash: hash} do
        transaction = insert(:transaction) |> with_block()
        log = insert_bridge_log(transaction, address: contract, index: 3)

        # same event from another contract, and another event from the bridge contract
        insert_bridge_log(transaction, address: insert(:address), index: 4)

        insert(:log,
          address: contract,
          transaction: transaction,
          block: transaction.block,
          block_number: transaction.block_number,
          index: 5,
          first_topic: "0x" <> String.duplicate("ab", 32)
        )

        assert [%{index: 3} = result] = BridgeDeposit.unprocessed_logs(hash, 10)
        assert result.block_hash == transaction.block_hash
        assert result.transaction_hash == transaction.hash
        assert result.block_number == transaction.block_number
        assert result.second_topic == log.second_topic
        assert result.third_topic == log.third_topic
        assert result.data == log.data
      end

      test "skips logs that already have a deposit", %{contract: contract, contract_address_hash: hash} do
        transaction = insert(:transaction) |> with_block()
        insert_bridge_log(transaction, address: contract, index: 3)
        insert_bridge_log(transaction, address: contract, index: 4)

        insert(:gravity_bridge_deposit,
          block_hash: transaction.block_hash,
          block_number: transaction.block_number,
          transaction_hash: transaction.hash,
          log_index: 3
        )

        assert [%{index: 4}] = BridgeDeposit.unprocessed_logs(hash, 10)
      end

      test "skips logs whose block lost consensus", %{contract: contract, contract_address_hash: hash} do
        transaction = insert(:transaction) |> with_block()
        insert_bridge_log(transaction, address: contract, index: 3)

        Repo.update_all(from(b in Block, where: b.hash == ^transaction.block_hash), set: [consensus: false])
        Repo.update_all(from(t in Transaction, where: t.hash == ^transaction.hash), set: [block_consensus: false])

        assert [] = BridgeDeposit.unprocessed_logs(hash, 10)
      end

      test "orders by block number and log index and respects the limit", %{
        contract: contract,
        contract_address_hash: hash
      } do
        newer = insert(:transaction) |> with_block()
        older_block = insert(:block, number: newer.block_number - 10)
        older = insert(:transaction) |> with_block(older_block)

        insert_bridge_log(newer, address: contract, index: 1)
        insert_bridge_log(older, address: contract, index: 7)
        insert_bridge_log(older, address: contract, index: 2)

        assert [%{index: 2}, %{index: 7}] = BridgeDeposit.unprocessed_logs(hash, 2)
      end
    end
  end
end
