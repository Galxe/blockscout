# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Repo.Gravity.Migrations.CreateGravityBridgeDeposits do
  use Ecto.Migration

  def change do
    create table(:gravity_bridge_deposits, primary_key: false) do
      add(:block_hash, :bytea, null: false, primary_key: true)
      add(:log_index, :integer, null: false, primary_key: true)
      add(:block_number, :bigint, null: false)
      add(:transaction_hash, :bytea, null: false)
      add(:recipient_address_hash, :bytea, null: false)
      add(:amount, :numeric, precision: 100, null: false)
      add(:nonce, :numeric, precision: 39, null: false)
      timestamps(null: false, type: :utc_datetime_usec)
    end

    create(
      index(:gravity_bridge_deposits, ["recipient_address_hash", "block_number DESC", "log_index DESC"],
        name: :gravity_bridge_deposits_recipient_block_number_log_index_index
      )
    )

    create(index(:gravity_bridge_deposits, [:transaction_hash]))
  end
end
