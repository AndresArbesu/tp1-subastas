defmodule Admin do
  def start_server do
    initial_state = %{auctions: %{}, next_id: 1}

    spawn(fn -> loop(initial_state) end)
  end

  defp loop(state) do
    receive do
      {:ping, requester} ->
        send(requester, :pong)
        loop(state)
      {:create_auction, requester, product_name, price, duration} ->
        auction_id = state.next_id
        auction_pid = Auction.start(auction_id, product_name, price, duration)
        send(requester, {:ok, auction_id})
        loop(state)
    end
  end

  def create_auction(admin_pid, product_name, price, duration) do
    send(admin_pid, {:create_auction, self(), product_name, price, duration})
  end

end
