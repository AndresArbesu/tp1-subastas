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

      {:get_auction_directory, requester, request_ref} ->
        directory = Map.to_list(state.auctions)

        send(requester, {request_ref, {:ok, directory}})
        loop(state)

      {:resolve_auction, requester, request_ref, auction_id} ->
        case Map.fetch(state.auctions, auction_id) do
          {:ok, auction_pid} ->
            send(requester, {request_ref, {:ok, auction_pid}})

          :error ->
            send(requester, {request_ref, {:error, :auction_not_found}})
        end

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

  defp resolve_auction(admin_pid, auction_id) do
  request_ref = make_ref()

  send(
    admin_pid,
    {:resolve_auction, self(), request_ref, auction_id}
  )

  receive do
    {^request_ref, response} ->
      response
  after
    2_000 ->
      {:error, :timeout}
  end
end


  def consult_auction(admin_pid, auction_id) do
    case resolve_auction(admin_pid, auction_id) do
      {:ok, auction_pid} ->
        Auction.consult(auction_pid)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_auction_directory(admin_pid) do
    request_ref = make_ref()

    send(admin_pid, {:get_auction_directory, self(), request_ref})

    receive do
      {^request_ref, response} ->
        response
    after
      2_000 ->
        {:error, :timeout}
    end
  end

  def list_active_auctions(admin_pid) do
    case get_auction_directory(admin_pid) do
      {:ok, directory} ->
        Enum.reduce_while(directory, {:ok, []}, fn
          {_auction_id, auction_pid}, {:ok, summaries} ->
            case Auction.consult(auction_pid) do
              {:ok, %{status: :active} = info} ->
                summary = Map.take(info, [:id, :product_name, :highest_bid])
                {:cont, {:ok, [summary | summaries]}}

              {:ok, %{status: :closed}} ->
                {:cont, {:ok, summaries}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end



end
