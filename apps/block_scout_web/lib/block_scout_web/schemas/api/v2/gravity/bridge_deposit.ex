# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.Schemas.API.V2.Gravity.BridgeDeposit do
  @moduledoc """
  This module defines the schema for the Gravity.BridgeDeposit struct.
  """
  require OpenApiSpex

  alias BlockScoutWeb.Schemas.API.V2.{Address, General}
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "GravityBridgeDeposit",
    description: "Native G credited by the Gravity bridge receiver (NativeMinted event).",
    type: :object,
    properties: %{
      transaction_hash: General.FullHash,
      block_hash: General.FullHash,
      block_number: %Schema{type: :integer, nullable: false},
      timestamp: General.Timestamp,
      log_index: %Schema{type: :integer, nullable: false},
      recipient: Address,
      amount: General.IntegerString,
      nonce: General.IntegerString
    },
    required: [:transaction_hash, :block_hash, :block_number, :timestamp, :log_index, :recipient, :amount, :nonce],
    additionalProperties: false
  })
end
