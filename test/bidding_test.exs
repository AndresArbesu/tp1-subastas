defmodule BiddingTest do
  use ExUnit.Case, async: true

  setup do
    admin = Admin.start_server()
    cleanup(admin)
    %{admin: admin}
  end

  test "valid bids strictly exceed the current reference, including own bids", %{admin: admin} do
    {id, _pid} = create(admin)
    assert AuctionClient.place_bid(admin, id, "ana", 1000) == {:error, {:bid_too_low, 1000}}
    assert AuctionClient.place_bid(admin, id, "ana", 1200) == {:ok, :bid_accepted}
    assert {:ok, before_rejection} = AuctionClient.consult_auction(admin, id)
    assert AuctionClient.place_bid(admin, id, "bruno", 1200) == {:error, {:bid_too_low, 1200}}
    assert AuctionClient.place_bid(admin, id, "bruno", 900) == {:error, {:bid_too_low, 1200}}
    assert AuctionClient.consult_auction(admin, id) == {:ok, before_rejection}
    assert AuctionClient.place_bid(admin, id, "ana", 1500) == {:ok, :bid_accepted}
    assert {:ok, state} = AuctionClient.consult_auction(admin, id)
    assert state.highest_bid == %{user: "ana", amount: 1500}
    assert state.accepted_bids_count == 2
  end

  test "invalid users and amounts are rejected without changing state", %{admin: admin} do
    {id, _pid} = create(admin)
    assert {:ok, original} = AuctionClient.consult_auction(admin, id)

    for user <- ["", "  ", nil, 12] do
      assert AuctionClient.place_bid(admin, id, user, 1200) == {:error, :invalid_user}
      assert AuctionClient.consult_auction(admin, id) == {:ok, original}
    end

    for amount <- [0, -1, 1.5, "1200", nil] do
      assert AuctionClient.place_bid(admin, id, "ana", amount) == {:error, :invalid_amount}
      assert AuctionClient.consult_auction(admin, id) == {:ok, original}
    end
  end

  test "a bid for an unknown ID reports a missing auction", %{admin: admin} do
    assert AuctionClient.place_bid(admin, 999, "ana", 1200) == {:error, :auction_not_found}
  end

  test "automatic close with bids preserves the winner and rejects later bids", %{admin: admin} do
    {id, pid} = create(admin, 500)
    assert AuctionClient.place_bid(admin, id, "ana", 1200) == {:ok, :bid_accepted}
    assert AuctionClient.place_bid(admin, id, "bruno", 1500) == {:ok, :bid_accepted}
    await_timer(pid)
    assert {:ok, closed} = AuctionClient.consult_auction(admin, id)
    assert closed.status == :closed
    assert closed.result == %{winner: "bruno", final_price: 1500}
    assert closed.highest_bid == %{user: "bruno", amount: 1500}
    assert closed.accepted_bids_count == 2
    assert AuctionClient.place_bid(admin, id, "carla", 2000) == {:error, :auction_closed}
    assert AuctionClient.consult_auction(admin, id) == {:ok, closed}
  end

  test "automatic close without bids has no winner or final price", %{admin: admin} do
    {id, pid} = create(admin, 300)
    await_timer(pid)
    assert {:ok, closed} = AuctionClient.consult_auction(admin, id)
    assert closed.status == :closed
    assert closed.result == %{winner: nil, final_price: nil}
    assert closed.highest_bid == nil
    assert closed.accepted_bids_count == 0
    assert AuctionClient.place_bid(admin, id, "ana", 2000) == {:error, :auction_closed}
    assert AuctionClient.consult_auction(admin, id) == {:ok, closed}
  end

  test "equal concurrent bids produce exactly one acceptance", %{admin: admin} do
    {id, _pid} = create(admin)
    requests = for number <- 1..20, do: {id, "user_#{number}", 1200}
    results = concurrent_bids(admin, requests)
    assert_consistent(admin, id, results, 1200)
    assert Enum.count(results, &(&1.response == {:ok, :bid_accepted})) == 1
  end

  test "distinct concurrent bids preserve the maximum and count only acceptances", %{admin: admin} do
    {id, _pid} = create(admin)
    requests = for number <- 1..20, do: {id, "user_#{number}", 1200 + number}
    results = concurrent_bids(admin, requests)
    assert_consistent(admin, id, results, 1220)
  end

  test "concurrent auctions retain independent bids, deadlines and final results", %{admin: admin} do
    {short_id, short_pid} = create(admin, 1500, "Keyboard")
    {long_id, _long_pid} = create(admin, 5000, "Monitor")

    requests =
      for number <- 1..20,
          {id, base} <- [{short_id, 1200}, {long_id, 2200}] do
        {id, "user_#{number}", base + number}
      end

    results = concurrent_bids(admin, requests)
    assert_consistent(admin, short_id, results, 1220)
    assert_consistent(admin, long_id, results, 2220)
    await_timer(short_pid)
    assert {:ok, short_closed} = AuctionClient.consult_auction(admin, short_id)
    assert short_closed.status == :closed
    assert short_closed.result == %{winner: "user_20", final_price: 1220}
    assert {:ok, long_before} = AuctionClient.consult_auction(admin, long_id)
    assert long_before.status == :active
    assert long_before.result == nil
    assert short_closed.expires_at < long_before.expires_at
    assert AuctionClient.place_bid(admin, short_id, "late", 9000) == {:error, :auction_closed}
    assert AuctionClient.consult_auction(admin, long_id) == {:ok, long_before}
    assert AuctionClient.place_bid(admin, long_id, "last", 3000) == {:ok, :bid_accepted}
    assert AuctionClient.consult_auction(admin, short_id) == {:ok, short_closed}
    wait_until(long_before.expires_at)
    assert {:ok, long_closed} = AuctionClient.consult_auction(admin, long_id)
    assert long_closed.status == :closed
    assert long_closed.result == %{winner: "last", final_price: 3000}
    assert long_closed.accepted_bids_count == long_before.accepted_bids_count + 1
    assert AuctionClient.consult_auction(admin, short_id) == {:ok, short_closed}
  end

  defp create(admin, duration \\ 10_000, product \\ "Keyboard") do
    AuctionClient.create_auction(admin, product, 1000, duration)
    assert_receive {:ok, id}, 1000
    ref = make_ref()
    send(admin, {:resolve_auction, self(), ref, id})
    assert_receive {^ref, {:ok, pid}}, 1000
    cleanup(pid)
    {id, pid}
  end

  defp cleanup(pid) do
    on_exit({:process, pid}, fn ->
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
    end)
  end

  defp await_timer(pid) do
    :erlang.trace(pid, true, [:receive, {:tracer, self()}])
    assert_receive {:trace, ^pid, :receive, :auction_expired}, 3000
    :erlang.trace(pid, false, [:receive])
  end

  defp wait_until(deadline) do
    Process.sleep(max(deadline - System.monotonic_time(:millisecond), 0))
  end

  defp concurrent_bids(admin, requests) do
    parent = self()
    run_ref = make_ref()

    workers =
      Enum.map(requests, fn {id, user, amount} ->
        pid =
          spawn(fn ->
            send(parent, {run_ref, :ready, self()})

            receive do
              {^run_ref, :start} ->
                response = AuctionClient.place_bid(admin, id, user, amount)
                operation = %{id: id, user: user, amount: amount, response: response}
                send(parent, {run_ref, :finished, self(), operation})
            after
              3000 -> exit(:start_timeout)
            end
          end)

        cleanup(pid)
        pid
      end)

    Enum.each(workers, fn pid ->
      assert_receive {^run_ref, :ready, ^pid}, 2000
    end)

    Enum.each(workers, &send(&1, {run_ref, :start}))

    Enum.map(workers, fn pid ->
      assert_receive {^run_ref, :finished, ^pid, operation}, 5000
      operation
    end)
  end

  defp assert_consistent(admin, id, results, maximum) do
    bids = Enum.filter(results, &(&1.id == id))
    accepted = Enum.filter(bids, &(&1.response == {:ok, :bid_accepted}))
    assert accepted != []

    Enum.each(bids, fn bid ->
      case bid.response do
        {:ok, :bid_accepted} -> :ok
        {:error, {:bid_too_low, reference}} -> assert bid.amount <= reference
        other -> flunk("unexpected bid response: #{inspect(other)}")
      end
    end)

    highest = Enum.max_by(accepted, & &1.amount)
    assert highest.amount == maximum
    assert {:ok, state} = AuctionClient.consult_auction(admin, id)
    assert state.status == :active
    assert state.highest_bid == %{user: highest.user, amount: maximum}
    assert state.accepted_bids_count == length(accepted)
    assert state.result == nil
  end
end
