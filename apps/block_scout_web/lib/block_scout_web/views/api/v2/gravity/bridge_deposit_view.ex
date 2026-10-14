# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.API.V2.Gravity.BridgeDepositView do
  use BlockScoutWeb, :view

  alias BlockScoutWeb.API.V2.Helper
  alias Explorer.Chain.Gravity.BridgeDeposit

  def render("bridge_deposits.json", %{deposits: deposits, next_page_params: next_page_params}) do
    %{"items" => Enum.map(deposits, &prepare_deposit/1), "next_page_params" => next_page_params}
  end

  @spec prepare_deposit(BridgeDeposit.t()) :: map()
  def prepare_deposit(deposit) do
    %{
      "transaction_hash" => deposit.transaction_hash,
      "block_hash" => deposit.block_hash,
      "block_number" => deposit.block_number,
      "timestamp" => deposit.block.timestamp,
      "log_index" => deposit.log_index,
      "recipient" => Helper.address_with_info(nil, deposit.recipient_address, deposit.recipient_address_hash, false),
      "amount" => deposit.amount,
      "nonce" => deposit.nonce
    }
  end
end
