# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.API.V2.Gravity.BridgeDepositController do
  @moduledoc """
  Rendering shared by the address and transaction bridge-deposit endpoints,
  which differ only in how the deposits are selected.
  """

  use BlockScoutWeb, :controller

  import BlockScoutWeb.Chain, only: [next_page_params: 5, paging_options: 1, split_list_by_page: 1]
  import Explorer.MicroserviceInterfaces.BENS, only: [maybe_preload_ens: 1]
  import Explorer.MicroserviceInterfaces.Metadata, only: [maybe_preload_metadata: 1]

  alias BlockScoutWeb.API.V2.Gravity.BridgeDepositView
  alias Explorer.Chain.Gravity.BridgeDeposit

  @spec render_list(Plug.Conn.t(), map(), (keyword() -> [BridgeDeposit.t()])) :: Plug.Conn.t()
  def render_list(conn, params, fetch_deposits) do
    full_options =
      [
        necessity_by_association: %{
          [recipient_address: [:scam_badge, :names, :smart_contract, proxy_implementations_association()]] => :optional
        },
        api?: true
      ]
      |> Keyword.merge(paging_options(params))

    {deposits, next_page} =
      full_options
      |> fetch_deposits.()
      |> split_list_by_page()

    next_page_params =
      next_page_params(next_page, deposits, params, false, &%{block_number: &1.block_number, index: &1.log_index})

    conn
    |> put_status(200)
    |> put_view(BridgeDepositView)
    |> render(:bridge_deposits, %{
      deposits: deposits |> maybe_preload_ens() |> maybe_preload_metadata(),
      next_page_params: next_page_params
    })
  end
end
