defmodule AuctionTest do
  use ExUnit.Case, async: true

  describe "validate_creation_params/3" do
    test "accepts valid creation data" do
      assert Auction.validate_creation_params("Keyboard", 1000, 30_000) == :ok
    end

    test "accepts positive integer boundary values" do
      assert Auction.validate_creation_params("K", 1, 1) == :ok
    end

    for product <- [nil, 123, :keyboard, [], "", "   ", "\t\n"] do
      test "rejects invalid product #{inspect(product)}" do
        assert Auction.validate_creation_params(unquote(Macro.escape(product)), 1000, 1000) ==
                 {:error, :invalid_product}
      end
    end

    for price <- [nil, "1000", 1.5, 0, -1] do
      test "rejects invalid price #{inspect(price)}" do
        assert Auction.validate_creation_params("Keyboard", unquote(price), 1000) ==
                 {:error, :invalid_price}
      end
    end

    for duration <- [nil, "1000", 1.5, 0, -1] do
      test "rejects invalid duration #{inspect(duration)}" do
        assert Auction.validate_creation_params("Keyboard", 1000, unquote(duration)) ==
                 {:error, :invalid_duration}
      end
    end
  end

  describe "auction process" do
    test "reports readiness with its ID and PID after preparing its state" do
      before_start = System.monotonic_time(:millisecond)
      pid = start_auction(7, "Keyboard", 1000, 10_000)
      after_ready = System.monotonic_time(:millisecond)

      assert {:ok, state} = Auction.consult(pid)
      assert state.id == 7
      assert state.product_name == "Keyboard"
      assert state.initial_price == 1000
      assert state.duration_ms == 10_000
      assert state.status == :active
      assert state.highest_bid == nil
      assert state.accepted_bids_count == 0
      assert state.expires_at >= before_start + 10_000
      assert state.expires_at <= after_ready + 10_000
    end

    test "repeated consultations do not change its state" do
      pid = start_auction(1, "Keyboard", 1000, 10_000)
      assert {:ok, first} = Auction.consult(pid)
      assert Auction.consult(pid) == {:ok, first}
    end

    test "keeps different auctions independent" do
      first = start_auction(1, "Keyboard", 1000, 10_000)
      second = start_auction(2, "Monitor", 5000, 20_000)

      assert first != second

      assert {:ok, %{id: 1, product_name: "Keyboard", initial_price: 1000}} =
               Auction.consult(first)

      assert {:ok, %{id: 2, product_name: "Monitor", initial_price: 5000}} =
               Auction.consult(second)
    end

    test "closes automatically without any consultation triggering the close" do
      pid = start_auction(1, "Keyboard", 1000, 60)
      # Observe the real timer message before sending any consultation.
      # Tracing does not replace the timer or change the production code.
      :erlang.trace(pid, true, [:receive, {:tracer, self()}])
      assert_receive {:trace, ^pid, :receive, :auction_expired}, 1000
      :erlang.trace(pid, false, [:receive])

      assert {:ok, %{status: :closed}} = Auction.consult(pid)
    end

    test "closed auction remains alive, consultable and responsive" do
      pid = start_auction(1, "Keyboard", 1000, 30)
      assert_closed(pid)
      assert Process.alive?(pid)
      assert {:ok, %{status: :closed, product_name: "Keyboard", id: 1}} = Auction.consult(pid)
      send(pid, {:ping, self()})
      assert_receive :pong, 1000
    end

    test "consultation only consumes its matching response" do
      pid = start_auction(1, "Keyboard", 1000, 10_000)
      unrelated_ref = make_ref()
      send(self(), {unrelated_ref, {:ok, :unrelated}})

      assert {:ok, %{id: 1}} = Auction.consult(pid)
      assert_receive {^unrelated_ref, {:ok, :unrelated}}
    end

    test "consultation returns timeout for a terminated process" do
      pid = start_auction(1, "Keyboard", 1000, 10_000)
      stop_process(pid)
      assert Auction.consult(pid) == {:error, :timeout}
    end
  end

  defp start_auction(id, product, price, duration) do
    pid = Auction.start(id, product, price, duration)
    on_exit({:auction, pid}, fn -> stop_process(pid) end)
    assert_receive {:auction_ready, ^id, ^pid}, 1000
    pid
  end

  defp assert_closed(pid) do
    deadline = System.monotonic_time(:millisecond) + 1000
    wait_until_closed(pid, deadline)
  end

  defp wait_until_closed(pid, deadline) do
    case Auction.consult(pid) do
      {:ok, %{status: :closed}} ->
        :ok

      {:ok, %{status: :active}} ->
        assert System.monotonic_time(:millisecond) < deadline,
               "auction did not close before the test deadline"

        Process.sleep(10)
        wait_until_closed(pid, deadline)

      other ->
        flunk("unexpected consultation result: #{inspect(other)}")
    end
  end

  defp stop_process(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
  end
end
