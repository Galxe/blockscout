# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.API.V2.Gravity.BridgeDepositControllerTest do
  use BlockScoutWeb.ConnCase
  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  # ConnCase does not import Ecto.Query or alias Repo.
  import Ecto.Query, only: [from: 2]

  alias Explorer.Repo
  alias Explorer.Chain.{Address, Block}

  if @chain_type == :gravity do
    describe "/addresses/{address_hash}/gravity/bridge-deposits" do
      test "returns an empty list for an unknown address", %{conn: conn} do
        address = build(:address)

        request = get(conn, "/api/v2/addresses/#{address.hash}/gravity/bridge-deposits")

        assert %{"items" => [], "next_page_params" => nil} = json_response(request, 200)
      end

      test "returns 422 on an invalid address", %{conn: conn} do
        request = get(conn, "/api/v2/addresses/invalid/gravity/bridge-deposits")

        assert json_response(request, 422)
      end

      test "returns the deposits newest first, paginated", %{conn: conn} do
        recipient = insert(:address)
        deposits = insert_list(51, :gravity_bridge_deposit, recipient_address_hash: recipient.hash)

        request = get(conn, "/api/v2/addresses/#{recipient.hash}/gravity/bridge-deposits")
        assert %{"items" => first_page, "next_page_params" => next_page_params} = json_response(request, 200)
        assert length(first_page) == 50
        assert %{"block_number" => _, "index" => _} = next_page_params

        request = get(conn, "/api/v2/addresses/#{recipient.hash}/gravity/bridge-deposits", next_page_params)
        assert %{"items" => second_page, "next_page_params" => nil} = json_response(request, 200)

        assert Enum.map(first_page ++ second_page, & &1["transaction_hash"]) ==
                 deposits |> Enum.reverse() |> Enum.map(&to_string(&1.transaction_hash))

        newest = List.last(deposits)
        newest_json = hd(first_page)
        assert newest_json["block_number"] == newest.block_number
        assert newest_json["log_index"] == newest.log_index
        assert newest_json["recipient"]["hash"] == Address.checksum(recipient.hash)
        assert newest_json["amount"] == to_string(newest.amount.value)
        assert newest_json["nonce"] == to_string(newest.nonce)
        assert newest_json["timestamp"]
      end

      test "hides deposits of non-consensus blocks", %{conn: conn} do
        deposit = insert(:gravity_bridge_deposit)
        Repo.update_all(from(b in Block, where: b.hash == ^deposit.block_hash), set: [consensus: false])

        request = get(conn, "/api/v2/addresses/#{deposit.recipient_address_hash}/gravity/bridge-deposits")

        assert %{"items" => []} = json_response(request, 200)
      end
    end

    describe "/transactions/{transaction_hash}/gravity/bridge-deposits" do
      test "returns every credit of the transaction, newest log first", %{conn: conn} do
        transaction = insert(:transaction) |> with_block()

        for log_index <- [3, 4] do
          insert(:gravity_bridge_deposit,
            block_hash: transaction.block_hash,
            block_number: transaction.block_number,
            transaction_hash: transaction.hash,
            log_index: log_index
          )
        end

        insert(:gravity_bridge_deposit)

        request = get(conn, "/api/v2/transactions/#{transaction.hash}/gravity/bridge-deposits")

        assert %{"items" => [%{"log_index" => 4}, %{"log_index" => 3}], "next_page_params" => nil} =
                 json_response(request, 200)
      end

      test "returns 404 for an unknown transaction", %{conn: conn} do
        transaction = build(:transaction)

        request = get(conn, "/api/v2/transactions/#{transaction.hash}/gravity/bridge-deposits")

        assert json_response(request, 404)
      end

      test "returns 422 on an invalid hash", %{conn: conn} do
        request = get(conn, "/api/v2/transactions/0x/gravity/bridge-deposits")

        assert json_response(request, 422)
      end
    end

    describe "/addresses/{address_hash}/tabs-counters" do
      test "counts consensus bridge deposits", %{conn: conn} do
        recipient = insert(:address)
        insert_list(2, :gravity_bridge_deposit, recipient_address_hash: recipient.hash)
        hidden = insert(:gravity_bridge_deposit, recipient_address_hash: recipient.hash)
        Repo.update_all(from(b in Block, where: b.hash == ^hidden.block_hash), set: [consensus: false])

        request = get(conn, "/api/v2/addresses/#{recipient.hash}/tabs-counters")

        assert %{"gravity_bridge_deposits_count" => 2} = json_response(request, 200)
      end
    end

    describe "/addresses/{address_hash}/coin-balance-history" do
      test "links the balance change at a deposit block to the mint transaction", %{conn: conn} do
        deposit = insert(:gravity_bridge_deposit)

        insert(:fetched_balance,
          address_hash: deposit.recipient_address_hash,
          block_number: deposit.block_number,
          value_fetched_at: DateTime.utc_now()
        )

        request = get(conn, "/api/v2/addresses/#{deposit.recipient_address_hash}/coin-balance-history")

        assert %{"items" => [item]} = json_response(request, 200)
        assert item["transaction_hash"] == to_string(deposit.transaction_hash)
      end
    end
  end
end
