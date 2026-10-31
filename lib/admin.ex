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
        case Auction.validate_creation_params(product_name, price, duration) do
          :ok ->
            auction_id = state.next_id
            auction_pid = Auction.start(auction_id, product_name, price, duration)
            monitor_ref = Process.monitor(auction_pid)

            receive do
              {:auction_ready, ^auction_id, ^auction_pid} ->
                Process.demonitor(monitor_ref, [:flush])

                updated_auctions =
                  Map.put(state.auctions, auction_id, auction_pid)

                new_state = %{
                  state
                  | auctions: updated_auctions,
                    next_id: state.next_id + 1
                }

                send(requester, {:ok, auction_id})
                loop(new_state)

              {:DOWN, ^monitor_ref, :process, ^auction_pid, reason} ->
                send(requester, {:error, {:auction_start_failed, reason}})
                loop(state)
            after
              2_000 ->
                Process.exit(auction_pid, :kill)
                Process.demonitor(monitor_ref, [:flush])

                send(requester, {:error, :auction_start_timeout})
                loop(state)
            end

          {:error, reason} ->
            send(requester, {:error, reason})
            loop(state)
        end
    end
  end

  def create_auction(admin_pid, product_name, price, duration) do
    send(admin_pid, {:create_auction, self(), product_name, price, duration})
  end
end
