# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Indexer.Transform.AddressesGravityTest do
  # The upstream `addresses.exs` lacks the `_test` suffix in this release, so `mix test` skips it.
  use ExUnit.Case, async: true

  alias Indexer.Transform.Addresses

  test "gravity bridge deposits extract the recipient with the deposit block" do
    recipient = "0x491398ade3125c2ee33756f6d22d070589576c74"

    assert [%{hash: ^recipient, fetched_coin_balance_block_number: 15_436_225}] =
             Addresses.extract_addresses(%{
               gravity_bridge_deposits: [
                 %{recipient_address_hash: recipient, block_number: 15_436_225, log_index: 3},
                 %{recipient_address_hash: recipient, block_number: 15_436_225, log_index: 6}
               ]
             })
  end
end
