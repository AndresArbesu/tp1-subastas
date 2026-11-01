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

  def place_bid(auction_pid, user, amount) do
    request_ref = make_ref()

    send(auction_pid, {:place_bid, self(), request_ref, user, amount})

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
        updated_state = close_if_expired(state)

        send(requester, {:status, updated_state.status})
        loop(updated_state)

      {:consult, requester, request_ref} ->
        updated_state = close_if_expired(state)

        send(requester, {request_ref, {:ok, updated_state}})
        loop(updated_state)

      {:place_bid, requester, request_ref, user, amount} ->
        current_state = close_if_expired(state)
        {response, next_state} = apply_bid(current_state, user, amount)

        send(requester, {request_ref, response})
        loop(next_state)
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

  def validate_bid_params(user, amount) do
    cond do
      not is_binary(user) ->
        {:error, :invalid_user}

      String.trim(user) == "" ->
        {:error, :invalid_user}

      not is_integer(amount) or amount <= 0 ->
        {:error, :invalid_amount}

      true ->
        :ok
    end
  end

  defp apply_bid(%{status: :closed} = state, _user, _amount) do
    {{:error, :auction_closed}, state}
  end

  defp apply_bid(state, user, amount) do
    case validate_bid_params(user, amount) do
      :ok ->
        reference =
          case state.highest_bid do
            nil ->
              state.initial_price

            %{amount: highest_amount} ->
              highest_amount
          end

        if amount > reference do
          updated_state = %{
            state
            | highest_bid: %{user: user, amount: amount},
              accepted_bids_count: state.accepted_bids_count + 1
          }

          {{:ok, :bid_accepted}, updated_state}
        else
          {{:error, {:bid_too_low, reference}}, state}
        end

      {:error, reason} ->
        {{:error, reason}, state}
    end
  end


  defp close_if_expired(state) do
    now = System.monotonic_time(:millisecond)

    if state.status == :active and now >= state.expires_at do
      %{state | status: :closed}
    else
      state
    end
  end

end
