defmodule Auction do
  def start(auction_id, product_name, price, duration) do
    creator_pid = self()

    spawn(fn ->
      started_at = System.monotonic_time(:millisecond)

      initial_state = %{
        id: auction_id,
        product_name: product_name,
        initial_price: price,
        duration_ms: duration,
        expires_at: started_at + duration,
        status: :active,
        highest_bid: nil,
        accepted_bids_count: 0
      }

      Process.send_after(self(), :auction_expired, duration)
      send(creator_pid, {:auction_ready, auction_id, self()})
      loop(initial_state)
    end)
  end

  def consult(auction_pid) do
    request_ref = make_ref()

    send(auction_pid, {:consult, self(), request_ref})

    receive do
      {^request_ref, response} ->
        response
    after
      2_000 ->
        {:error, :timeout}
    end
  end


  defp loop(state) do
    receive do
      {:ping, requester} ->
        send(requester, :pong)
        loop(state)

      :auction_expired ->
        new_state = %{state | status: :closed}
        loop(new_state)

      {:get_status, requester} ->
        send(requester, {:status, state.status})
        loop(state)

      {:consult, requester, request_ref} ->
        send(requester, {request_ref, {:ok, state}})
        loop(state)
    end
  end

  def validate_creation_params(product_name, price, duration) do
    cond do
      not is_binary(product_name) ->
        {:error, :invalid_product}

      String.trim(product_name) == "" ->
        {:error, :invalid_product}

      not is_integer(price) or price <= 0 ->
        {:error, :invalid_price}

      not is_integer(duration) or duration <= 0 ->
        {:error, :invalid_duration}

      true ->
        :ok
    end
  end
end
