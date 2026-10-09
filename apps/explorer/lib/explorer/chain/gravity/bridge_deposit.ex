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

  alias Explorer.{Chain, PagingOptions, Repo}
  alias Explorer.Chain.{Address, Block, Hash, Log, Wei}

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
  Returns up to `limit` NativeMinted logs of `contract_address_hash` in
  consensus blocks that have no deposit row yet, oldest first.

  Looking for missing rows instead of keeping a cursor makes the result
  independent of the order in which blocks were indexed (catchup indexes from
  the head backwards), so the same call serves the backfill and new blocks.
  """
  @spec unprocessed_logs(Hash.Address.t(), pos_integer()) :: [map()]
  def unprocessed_logs(contract_address_hash, limit) do
    contract_address_hash
    |> Log.address_match_union_query(
      fn address_match_dynamic ->
        Log
        |> Log.join_transaction_query()
        |> where(^address_match_dynamic)
        |> where(as(:transaction).block_consensus == true)
        |> Log.filter_by_topic_query(:first_topic, @event_signature)
        |> join(:left, [log, transaction: transaction], deposit in __MODULE__,
          as: :deposit,
          on: deposit.block_hash == transaction.block_hash and deposit.log_index == log.index
        )
        |> where([deposit: deposit], is_nil(deposit.block_hash))
        |> select([log, transaction: transaction], %{
          block_number: log.block_number,
          block_hash: transaction.block_hash,
          transaction_hash: transaction.hash,
          index: log.index,
          second_topic: log.second_topic,
          third_topic: log.third_topic,
          data: log.data,
          compressed_data: log.compressed_data
        })
      end,
      fn query ->
        query
        |> order_by([log], asc: log.block_number, asc: log.index)
        |> limit(^limit)
      end
    )
    |> Repo.all()
    |> Log.prepare_data()
  end

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
