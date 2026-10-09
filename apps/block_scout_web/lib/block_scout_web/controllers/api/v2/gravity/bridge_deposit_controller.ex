# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.API.V2.Gravity.BridgeDepositController do
  @moduledoc """
  Rendering shared by the address and transaction bridge-deposit endpoints,
  which differ only in how the deposits are selected.
  """

  use BlockScoutWeb, :controller

  import BlockScoutWeb.Chain, only: [paginate_list: 4, paging_options: 1]
  import Explorer.Chain.Address.MetadataPreloader, only: [maybe_preload_ens_and_metadata: 1]

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

    {deposits, next_page_params} =
      full_options
      |> fetch_deposits.()
      |> paginate_list(params, full_options[:paging_options],
        paging_function: &%{block_number: &1.block_number, index: &1.log_index}
      )

    conn
    |> put_status(200)
    |> put_view(BridgeDepositView)
    |> render(:bridge_deposits, %{
      deposits: maybe_preload_ens_and_metadata(deposits),
      next_page_params: next_page_params
    })
  end
end
