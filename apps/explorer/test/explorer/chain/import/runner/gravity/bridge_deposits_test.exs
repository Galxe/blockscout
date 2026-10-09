# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Import.Runner.Gravity.BridgeDepositsTest do
  use Explorer.DataCase
  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  alias Explorer.Chain
  alias Explorer.Chain.Gravity.BridgeDeposit

  if @chain_type == :gravity do
    describe "Chain.import/1 with gravity_bridge_deposits" do
      test "inserts a deposit and skips a re-import of the same log" do
        transaction = insert(:transaction) |> with_block()
        recipient = insert(:address)

        params = %{
          block_hash: transaction.block_hash,
          log_index: 3,
          block_number: transaction.block_number,
          transaction_hash: transaction.hash,
          recipient_address_hash: recipient.hash,
          amount: 50_000 * 10 ** 18,
          nonce: 2151
        }

        assert {:ok, %{insert_gravity_bridge_deposits: [_]}} =
                 Chain.import(%{gravity_bridge_deposits: %{params: [params]}})

        assert {:ok, %{insert_gravity_bridge_deposits: []}} =
                 Chain.import(%{gravity_bridge_deposits: %{params: [params]}})

        assert [%BridgeDeposit{} = deposit] = Repo.all(BridgeDeposit)
        assert deposit.recipient_address_hash == recipient.hash
        assert Decimal.equal?(deposit.amount.value, 50_000 * 10 ** 18)
        assert Decimal.equal?(deposit.nonce, 2151)
      end

      test "rejects params without a recipient" do
        transaction = insert(:transaction) |> with_block()

        params = %{
          block_hash: transaction.block_hash,
          log_index: 3,
          block_number: transaction.block_number,
          transaction_hash: transaction.hash,
          amount: 1,
          nonce: 1
        }

        assert {:error, [%Ecto.Changeset{valid?: false}]} =
                 Chain.import(%{gravity_bridge_deposits: %{params: [params]}})
      end
    end
  end
end
