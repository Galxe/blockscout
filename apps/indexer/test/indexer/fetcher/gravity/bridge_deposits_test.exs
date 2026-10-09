# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Indexer.Fetcher.Gravity.BridgeDepositsTest do
  use Explorer.DataCase, async: false
  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  import ExUnit.CaptureLog, only: [capture_log: 1]

  alias Explorer.Chain.{Address, Data, Hash}
  alias Explorer.Chain.Address.CoinBalance
  alias Explorer.Chain.Gravity.BridgeDeposit
  alias Indexer.Fetcher.CoinBalance.Realtime.Supervisor, as: CoinBalanceRealtimeSupervisor
  alias Indexer.Fetcher.Gravity.BridgeDeposits

  @contract_address "0x595475934ed7d9faa7fca28341c2ce583904a44e"

  if @chain_type == :gravity do
    setup do
      # The realtime coin balance fetcher is not running in tests. Disabling it
      # turns the push into a no-op and leaves the NULL-value rows that the
      # catchup fetcher would pick up after a restart.
      initial = Application.get_env(:indexer, CoinBalanceRealtimeSupervisor)
      Application.put_env(:indexer, CoinBalanceRealtimeSupervisor, Keyword.merge(initial || [], disabled?: true))
      on_exit(fn -> Application.put_env(:indexer, CoinBalanceRealtimeSupervisor, initial) end)

      contract = insert(:address, hash: @contract_address)
      {:ok, contract_address_hash} = Hash.Address.cast(@contract_address)

      %{contract: contract, state: %BridgeDeposits{contract_address_hash: contract_address_hash, interval: 1}}
    end

    defp insert_bridge_log(contract, transaction, attrs) do
      insert(
        :gravity_bridge_deposit_log,
        Map.merge(
          %{
            address: contract,
            transaction: transaction,
            block: transaction.block,
            block_number: transaction.block_number
          },
          Map.new(attrs)
        )
      )
    end

    defp coin_balances(address_hash) do
      Repo.all(from(cb in CoinBalance, where: cb.address_hash == ^address_hash))
    end

    test "imports the deposit, the recipient and a coin balance row to fetch", %{contract: contract, state: state} do
      recipient = address_hash()
      transaction = insert(:transaction) |> with_block()
      insert_bridge_log(contract, transaction, deposit_recipient_address_hash: recipient, deposit_nonce: 2151, index: 3)

      assert {:ok, 1} = BridgeDeposits.process_batch(state)

      assert [%BridgeDeposit{recipient_address_hash: ^recipient, log_index: 3} = deposit] = Repo.all(BridgeDeposit)
      assert deposit.block_number == transaction.block_number
      assert Decimal.equal?(deposit.nonce, 2151)
      assert Repo.get(Address, recipient)

      block_number = transaction.block_number
      assert [%CoinBalance{block_number: ^block_number, value: nil, value_fetched_at: nil}] = coin_balances(recipient)
    end

    test "imports nothing on the next batch", %{contract: contract, state: state} do
      transaction = insert(:transaction) |> with_block()
      insert_bridge_log(contract, transaction, index: 3)

      assert {:ok, 1} = BridgeDeposits.process_batch(state)
      assert {:ok, 0} = BridgeDeposits.process_batch(state)
      assert Repo.aggregate(BridgeDeposit, :count) == 1
    end

    test "processes a log of an older block indexed after a newer one", %{contract: contract, state: state} do
      newer = insert(:transaction) |> with_block()
      insert_bridge_log(contract, newer, index: 1)
      assert {:ok, 1} = BridgeDeposits.process_batch(state)

      older = insert(:transaction) |> with_block(insert(:block, number: newer.block_number - 10))
      insert_bridge_log(contract, older, index: 1)
      assert {:ok, 1} = BridgeDeposits.process_batch(state)

      assert Repo.aggregate(BridgeDeposit, :count) == 2
    end

    test "keeps an already fetched coin balance value", %{contract: contract, state: state} do
      recipient = insert(:address)
      transaction = insert(:transaction) |> with_block()

      insert(:fetched_balance,
        address_hash: recipient.hash,
        block_number: transaction.block_number,
        value: 42,
        value_fetched_at: DateTime.utc_now()
      )

      insert_bridge_log(contract, transaction, deposit_recipient_address_hash: recipient.hash, index: 3)

      assert {:ok, 1} = BridgeDeposits.process_batch(state)
      assert [%CoinBalance{value: value}] = coin_balances(recipient.hash)
      assert Decimal.equal?(value.value, 42)
    end

    test "deduplicates recipient and coin balance rows", %{contract: contract, state: state} do
      recipient = address_hash()
      transaction = insert(:transaction) |> with_block()
      insert_bridge_log(contract, transaction, deposit_recipient_address_hash: recipient, index: 3)
      insert_bridge_log(contract, transaction, deposit_recipient_address_hash: recipient, index: 4)

      assert {:ok, 2} = BridgeDeposits.process_batch(state)
      assert Repo.aggregate(BridgeDeposit, :count) == 2
      assert [_] = coin_balances(recipient)
    end

    test "reports a full batch so the next one runs immediately", %{contract: contract, state: state} do
      state = %{state | batch_size: 1}
      transaction = insert(:transaction) |> with_block()
      insert_bridge_log(contract, transaction, index: 3)
      insert_bridge_log(contract, transaction, index: 4)

      assert {:ok, 1} = BridgeDeposits.process_batch(state)
      assert {:ok, 1} = BridgeDeposits.process_batch(state)
      assert {:ok, 0} = BridgeDeposits.process_batch(state)
    end

    test "stops at a malformed log and imports nothing from the batch", %{contract: contract, state: state} do
      transaction = insert(:transaction) |> with_block()
      insert_bridge_log(contract, transaction, index: 3)
      bad = %Data{bytes: <<1::size(248)>>}
      insert_bridge_log(contract, transaction, index: 4, data: bad, compressed_data: bad)

      assert {:error, {:malformed_log, %{index: 4}}} = BridgeDeposits.process_batch(state)
      assert Repo.aggregate(BridgeDeposit, :count) == 0

      assert capture_log(fn -> BridgeDeposits.handle_info(:process_logs, state) end) =~ "malformed_log"
    end

    test "refuses to start with an invalid contract address" do
      initial = Application.get_env(:indexer, BridgeDeposits)
      Application.put_env(:indexer, BridgeDeposits, Keyword.merge(initial || [], contract_address: "0x1234"))
      on_exit(fn -> Application.put_env(:indexer, BridgeDeposits, initial) end)

      assert_raise MatchError, fn -> BridgeDeposits.init([]) end
    end
  end
end
