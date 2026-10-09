# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Gravity.BridgeDeposit do
  @moduledoc """
  Native G credited to an address by the Gravity bridge receiver contract.

  The mint precompile writes the recipient's balance directly, so neither the
  transaction nor any internal transaction carries the amount. Deposits are
  built from the receiver's
  `NativeMinted(address indexed recipient, uint256 amount, uint128 indexed nonce)`
  events.
  """

  use Explorer.Schema

  alias Explorer.Chain.{Address, Block, Hash, Wei}

  @event_signature "0x28a48d0161bbc70613fb99402d1437dea020d82e4495b003eb642c78fa4e2584"

  @required_attrs ~w(block_hash log_index block_number transaction_hash recipient_address_hash amount nonce)a

  @primary_key false
  typed_schema "gravity_bridge_deposits" do
    field(:log_index, :integer, primary_key: true)
    field(:block_number, :integer, null: false)
    field(:transaction_hash, Hash.Full, null: false)
    field(:amount, Wei, null: false)
    field(:nonce, :decimal, null: false)

    belongs_to(:block, Block, foreign_key: :block_hash, references: :hash, type: Hash.Full, primary_key: true)

    belongs_to(:recipient_address, Address,
      foreign_key: :recipient_address_hash,
      references: :hash,
      type: Hash.Address,
      null: false
    )

    timestamps()
  end

  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(deposit, attrs) do
    deposit
    |> cast(attrs, @required_attrs)
    |> validate_required(@required_attrs)
  end

  @spec event_signature() :: String.t()
  def event_signature, do: @event_signature
end
