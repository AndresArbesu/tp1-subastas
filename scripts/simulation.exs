defmodule Simulation do
  def run do
    admin_pid = Admin.start_server()
    auction_ids = create_auctions(admin_pid)
    user_pids = start_users(admin_pid, auction_ids)
    wait_for_users(user_pids)

    signal_users(user_pids, :start)
    results = collect_results(user_pids, :user_finished)
    all_operations = List.flatten(results)
    print_early_summary(results, all_operations)

    wait_for_expiration(admin_pid, auction_ids)
    closed_snapshots = collect_closed_snapshots(admin_pid, auction_ids)

    signal_users(user_pids, :place_late_bids)
    late_results = collect_results(user_pids, :late_bids_finished)
    late_operations = List.flatten(late_results)

    check(
      length(results) == length(user_pids) and length(late_results) == length(user_pids),
      "missing user reports"
    )

    Enum.each(auction_ids, fn auction_id ->
      verify_auction(
        admin_pid,
        auction_id,
        length(user_pids),
        all_operations,
        late_operations,
        closed_snapshots
      )
    end)

    print_final_summary(late_results, all_operations, late_operations)
  end

  defp create_auctions(admin_pid) do
    Enum.map(
      [
        {"Keyboard", 10_000},
        {"Monitor", 12_000},
        {"Headphones", 14_000}
      ],
      fn {product, duration} ->
        AuctionClient.create_auction(admin_pid, product, 1000, duration)

        receive do
          {:ok, id} ->
            id

          {:error, reason} ->
            raise "Auction creation failed: #{inspect(reason)}"
        after
          3_000 ->
            raise "Auction creation timed out"
        end
      end
    )
  end

  defp start_users(admin_pid, auction_ids) do
    coordinator_pid = self()

    Enum.map(1..100, fn number ->
      spawn(fn -> run_user(coordinator_pid, admin_pid, auction_ids, number) end)
    end)
  end

  defp run_user(coordinator_pid, admin_pid, auction_ids, number) do
    user = "user_#{number}"
    send(coordinator_pid, {:user_ready, self()})

    receive do
      :start ->
        operations = early_operations(admin_pid, auction_ids, user, number)
        send(coordinator_pid, {:user_finished, self(), operations})
        wait_for_late_bids(coordinator_pid, admin_pid, auction_ids, user, number)
    after
      5_000 -> exit(:start_timeout)
    end
  end

  defp early_operations(admin_pid, auction_ids, user, number) do
    Enum.flat_map(auction_ids, fn auction_id ->
      consultation = %{
        type: :consult,
        auction_id: auction_id,
        user: user,
        response: AuctionClient.consult_auction(admin_pid, auction_id)
      }

      bids =
        Enum.map([1200, 900, 2000 + number], fn amount ->
          %{
            type: :bid,
            auction_id: auction_id,
            user: user,
            amount: amount,
            response: AuctionClient.place_bid(admin_pid, auction_id, user, amount)
          }
        end)

      [consultation | bids]
    end)
  end

  defp wait_for_late_bids(coordinator_pid, admin_pid, auction_ids, user, number) do
    receive do
      :place_late_bids ->
        operations = late_operations(admin_pid, auction_ids, user, number)
        send(coordinator_pid, {:late_bids_finished, self(), operations})
    after
      20_000 -> exit(:late_bids_start_timeout)
    end
  end

  defp late_operations(admin_pid, auction_ids, user, number) do
    Enum.map(auction_ids, fn auction_id ->
      amount = 3000 + number

      %{
        type: :bid,
        auction_id: auction_id,
        user: user,
        amount: amount,
        response: AuctionClient.place_bid(admin_pid, auction_id, user, amount)
      }
    end)
  end

  defp wait_for_users(user_pids) do
    Enum.each(user_pids, fn user_pid ->
      receive do
        {:user_ready, ^user_pid} ->
          :ok
      after
        3_000 ->
          raise "User did not become ready"
      end
    end)
  end

  defp signal_users(user_pids, signal) do
    Enum.each(user_pids, fn user_pid -> send(user_pid, signal) end)
  end

  defp collect_results(user_pids, tag) do
    Enum.map(user_pids, fn user_pid ->
      receive do
        {^tag, ^user_pid, operations} -> operations
      after
        5_000 -> raise "Missing #{tag} report from #{inspect(user_pid)}"
      end
    end)
  end

  defp print_early_summary(results, all_operations) do
    accepted_count =
      Enum.count(all_operations, fn operation ->
        operation.type == :bid and
          operation.response == {:ok, :bid_accepted}
      end)

    IO.puts("Users completed: #{length(results)}")
    IO.puts("User requests completed: #{length(all_operations)}")
    IO.puts("Accepted bids: #{accepted_count}")
  end

  defp wait_for_expiration(admin_pid, auction_ids) do
    latest_expiration =
      Enum.map(auction_ids, fn auction_id ->
        case AuctionClient.consult_auction(admin_pid, auction_id) do
          {:ok, state} ->
            state.expires_at

          {:error, reason} ->
            raise "Could not obtain auction deadline: #{inspect(reason)}"
        end
      end)
      |> Enum.max()

    remaining_ms =
      max(latest_expiration - System.monotonic_time(:millisecond), 0)

    Process.sleep(remaining_ms)

    IO.puts("All auction deadlines reached")
  end

  defp collect_closed_snapshots(admin_pid, auction_ids) do
    Map.new(auction_ids, fn auction_id ->
      case AuctionClient.consult_auction(admin_pid, auction_id) do
        {:ok, %{status: :closed} = state} ->
          {auction_id, state}

        {:ok, state} ->
          raise "Auction #{auction_id} is still #{inspect(state.status)}"

        {:error, reason} ->
          raise "Could not consult closed auction #{auction_id}: #{inspect(reason)}"
      end
    end)
  end

  defp verify_auction(
         admin_pid,
         auction_id,
         users_count,
         all_operations,
         late_operations,
         closed_snapshots
       ) do
    consultations =
      Enum.filter(all_operations, fn operation ->
        operation.auction_id == auction_id and operation.type == :consult
      end)

    early_bids =
      Enum.filter(all_operations, fn operation ->
        operation.auction_id == auction_id and operation.type == :bid
      end)

    late_bids =
      Enum.filter(late_operations, fn operation ->
        operation.auction_id == auction_id
      end)

    check(
      length(consultations) == users_count and
        length(early_bids) == users_count * 3 and
        length(late_bids) == users_count,
      "unexpected request counts for auction #{auction_id}"
    )

    Enum.each(consultations, fn operation ->
      case operation.response do
        {:ok, %{id: ^auction_id, status: :active}} ->
          :ok

        response ->
          raise "Unexpected early consultation: #{inspect(response)}"
      end
    end)

    Enum.each(early_bids, fn operation ->
      case operation.response do
        {:ok, :bid_accepted} ->
          :ok

        {:error, {:bid_too_low, reference}} ->
          check(operation.amount <= reference, "incorrect bid rejection")

        response ->
          raise "Unexpected early bid response: #{inspect(response)}"
      end
    end)

    accepted =
      Enum.filter(early_bids, fn operation ->
        operation.response == {:ok, :bid_accepted}
      end)

    check(accepted != [], "no accepted bids for auction #{auction_id}")

    highest_accepted = Enum.max_by(accepted, fn operation -> operation.amount end)
    highest_submitted = Enum.max_by(early_bids, fn operation -> operation.amount end)

    snapshot = Map.fetch!(closed_snapshots, auction_id)

    check(
      highest_accepted.amount == highest_submitted.amount,
      "highest submitted bid was not accepted for auction #{auction_id}"
    )

    check(
      snapshot.accepted_bids_count == length(accepted),
      "accepted bid count mismatch for auction #{auction_id}"
    )

    check(
      snapshot.highest_bid == %{
        user: highest_accepted.user,
        amount: highest_accepted.amount
      },
      "highest bid mismatch for auction #{auction_id}"
    )

    check(
      snapshot.result == %{
        winner: highest_accepted.user,
        final_price: highest_accepted.amount
      },
      "final result mismatch for auction #{auction_id}"
    )

    Enum.each(late_bids, fn operation ->
      check(
        operation.response == {:error, :auction_closed},
        "late bid was not rejected as closed for auction #{auction_id}"
      )
    end)

    case AuctionClient.consult_auction(admin_pid, auction_id) do
      {:ok, state} ->
        check(
          state == snapshot,
          "late bids changed the state of auction #{auction_id}"
        )

      response ->
        raise "Final consultation failed: #{inspect(response)}"
    end

    IO.puts(
      "Auction #{auction_id} (#{snapshot.product_name}): " <>
        "accepted=#{length(accepted)}, " <>
        "too_low=#{length(early_bids) - length(accepted)}, " <>
        "closed_rejections=#{length(late_bids)}, " <>
        "winner=#{snapshot.result.winner}, " <>
        "final_price=#{snapshot.result.final_price}"
    )
  end

  defp print_final_summary(late_results, all_operations, late_operations) do
    IO.puts("Participants completed: #{length(late_results)}")

    IO.puts("User requests completed: #{length(all_operations) + length(late_operations)}")

    IO.puts("Failures/timeouts: 0")
    IO.puts("Simulation passed")
  end

  defp check(condition, message) do
    unless condition do
      raise "Simulation failed: #{message}"
    end
  end
end

Simulation.run()
