defmodule Auction do
   def start(auction_id, product_name, price, duration) do
    initial_state = %{
      id: auction_id,
      product_name: product_name,
      initial_price: price,
      duration_ms: duration,
      status: :active,
      highest_bid: nil,
      accepted_bids_count: 0
    }
    spawn(fn-> loop(initial_state) end)
  end

   defp loop(state) do
    receive do
      {:ping, requester} ->
        send(requester, :pong)
        loop(state)
      end
    end

end
