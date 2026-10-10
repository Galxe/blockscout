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

  alias Explorer.{Chain, PagingOptions}
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

  @doc """
  Lists deposits credited to `address_hash`, newest first.
  """
  @spec from_address_hash(Hash.Address.t(), [Chain.paging_options() | Chain.necessity_by_association() | Chain.api?()]) ::
          [t()]
  def from_address_hash(address_hash, options \\ []) do
    __MODULE__
    |> where([deposit], deposit.recipient_address_hash == ^address_hash)
    |> list(options)
  end

  @doc """
  Lists deposits credited by `transaction_hash`, newest log first.
  """
  @spec from_transaction_hash(Hash.Full.t(), [
          Chain.paging_options() | Chain.necessity_by_association() | Chain.api?()
        ]) :: [t()]
  def from_transaction_hash(transaction_hash, options \\ []) do
    __MODULE__
    |> where([deposit], deposit.transaction_hash == ^transaction_hash)
    |> list(options)
  end

  @doc """
  Query of the consensus deposits credited to `address_hash`, for counters.
  """
  @spec address_hash_to_deposits_query(Hash.Address.t()) :: Ecto.Query.t()
  def address_hash_to_deposits_query(address_hash) do
    __MODULE__
    |> where([deposit], deposit.recipient_address_hash == ^address_hash)
    |> consensus_query()
  end

  @doc """
  Query of the transaction that credited `address_hash` at `block_number`.
  """
  @spec transaction_hash_query(Hash.Address.t(), non_neg_integer()) :: Ecto.Query.t()
  def transaction_hash_query(address_hash, block_number) do
    __MODULE__
    |> where([deposit], deposit.recipient_address_hash == ^address_hash and deposit.block_number == ^block_number)
    |> consensus_query()
    |> select([deposit], deposit.transaction_hash)
    |> limit(1)
  end

  defp list(query, options) do
    paging_options = Keyword.get(options, :paging_options, Chain.default_paging_options())
    necessity_by_association = Keyword.get(options, :necessity_by_association, %{})

    query
    |> consensus_query()
    |> page_deposits(paging_options)
    |> order_by([deposit], desc: deposit.block_number, desc: deposit.log_index)
    |> limit(^paging_options.page_size)
    |> preload([block: block], block: block)
    |> Chain.join_associations(necessity_by_association)
    |> Chain.select_repo(options).all()
  end

  # Deposits stay in the table when their block loses consensus; every read hides them.
  defp consensus_query(query) do
    join(query, :inner, [deposit], block in assoc(deposit, :block), as: :block, on: block.consensus == true)
  end

  defp page_deposits(query, %PagingOptions{key: {block_number, log_index}}) do
    where(query, [deposit], {deposit.block_number, deposit.log_index} < {^block_number, ^log_index})
  end

  defp page_deposits(query, _paging_options), do: query
end
