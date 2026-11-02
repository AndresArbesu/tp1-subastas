defmodule AdminTest do
  use ExUnit.Case, async: true

  setup do
    admin = Admin.start_server()
    on_exit(fn -> stop_process(admin) end)
    %{admin: admin}
  end

  test "admin continues responding to messages", %{admin: admin} do
    for _ <- 1..2 do
      send(admin, {:ping, self()})
      assert_receive :pong, 1000
    end
  end

  test "creates an auction that is immediately discoverable and consultable", %{admin: admin} do
    {id, pid} = create_auction(admin, "Keyboard", 1000, 10_000)

    assert Process.alive?(pid)

    assert {:ok, %{id: ^id, product_name: "Keyboard", status: :active}} =
             AuctionClient.consult_auction(admin, id)
  end

  test "assigns distinct IDs and preserves both registered processes", %{admin: admin} do
    {first_id, first_pid} = create_auction(admin, "Keyboard", 1000, 10_000)
    {second_id, second_pid} = create_auction(admin, "Monitor", 5000, 10_000)

    assert first_id != second_id
    assert first_pid != second_pid
    assert resolve(admin, first_id) == {:ok, first_pid}
    assert resolve(admin, second_id) == {:ok, second_pid}
  end

  for {label, product, price, duration, reason} <- [
        {"product", "   ", 1000, 1000, :invalid_product},
        {"price", "Keyboard", -1, 1000, :invalid_price},
        {"duration", "Keyboard", 1000, 0, :invalid_duration}
      ] do
    test "rejects invalid #{label} without consuming the next ID", %{admin: admin} do
      {first_id, first_pid} = create_auction(admin, "First", 1000, 10_000)

      AuctionClient.create_auction(admin, unquote(product), unquote(price), unquote(duration))
      assert_receive {:error, unquote(reason)}, 1000

      {second_id, _second_pid} = create_auction(admin, "Second", 1000, 10_000)
      assert second_id == first_id + 1
      assert resolve(admin, first_id) == {:ok, first_pid}
      assert Process.alive?(admin)
    end
  end

  test "discovery reports a missing auction without breaking later lookups", %{admin: admin} do
    assert resolve(admin, 999) == {:error, :auction_not_found}
    {id, pid} = create_auction(admin, "Keyboard", 1000, 10_000)
    assert resolve(admin, id) == {:ok, pid}
  end

  test "public consultation reports a missing auction", %{admin: admin} do
    assert AuctionClient.consult_auction(admin, 999) == {:error, :auction_not_found}
  end

  test "public consultation returns independent auction data", %{admin: admin} do
    {first_id, _} = create_auction(admin, "Keyboard", 1000, 10_000)
    {second_id, _} = create_auction(admin, "Monitor", 5000, 10_000)

    assert {:ok, first} = AuctionClient.consult_auction(admin, first_id)
    assert {:ok, second} = AuctionClient.consult_auction(admin, second_id)
    assert first.product_name == "Keyboard"
    assert first.initial_price == 1000
    assert second.product_name == "Monitor"
    assert second.initial_price == 5000
    assert first.highest_bid == nil
    assert first.accepted_bids_count == 0
    assert AuctionClient.consult_auction(admin, first_id) == {:ok, first}
  end

  test "a closed auction remains registered and publicly consultable", %{admin: admin} do
    {id, pid} = create_auction(admin, "Keyboard", 1000, 30)
    deadline = System.monotonic_time(:millisecond) + 1000
    wait_until_closed(admin, id, deadline)

    assert resolve(admin, id) == {:ok, pid}
    assert Process.alive?(pid)

    assert {:ok, %{id: ^id, status: :closed, product_name: "Keyboard"}} =
             AuctionClient.consult_auction(admin, id)
  end

  test "public consultation propagates discovery timeout for a terminated admin", %{admin: admin} do
    stop_process(admin)
    assert AuctionClient.consult_auction(admin, 1) == {:error, :timeout}
  end

  defp create_auction(admin, product, price, duration) do
    AuctionClient.create_auction(admin, product, price, duration)
    assert_receive {:ok, id}, 3000
    assert {:ok, pid} = resolve(admin, id)
    on_exit({:auction, pid}, fn -> stop_process(pid) end)
    {id, pid}
  end

  defp resolve(admin, id) do
    ref = make_ref()
    send(admin, {:resolve_auction, self(), ref, id})
    assert_receive {^ref, response}, 1000
    response
  end

  defp wait_until_closed(admin, id, deadline) do
    case AuctionClient.consult_auction(admin, id) do
      {:ok, %{status: :closed}} ->
        :ok

      {:ok, %{status: :active}} ->
        assert System.monotonic_time(:millisecond) < deadline,
               "auction did not close before the test deadline"

        Process.sleep(10)
        wait_until_closed(admin, id, deadline)

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
