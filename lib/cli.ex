defmodule CLI do
  def start do
    admin_pid = Admin.start_server()

    IO.puts("Auction system. Type help for available commands.")
    loop(admin_pid)
  end

  defp loop(admin_pid) do
    case IO.gets("> ") do
      :eof ->
        :ok

      {:error, reason} ->
        IO.puts("Input error: #{inspect(reason)}")
        :ok

      line ->
        case split_command(line) do
          ["help"] ->
            IO.puts("""
            Commands:
              help
              active
              create "PRODUCT" INITIAL_PRICE DURATION_MS
              show AUCTION_ID
              bid AUCTION_ID USER AMOUNT
              exit
            """)

            loop(admin_pid)

          ["exit"] ->
            :ok

          [] ->
            loop(admin_pid)

          ["active"] ->
            case AuctionClient.list_active_auctions(admin_pid) do
              {:ok, []} ->
                IO.puts("No active auctions.")

              {:ok, summaries} ->
                Enum.each(summaries, fn summary ->
                  bid_text =
                    case summary.highest_bid do
                      nil ->
                        "no bids"

                      %{user: user, amount: amount} ->
                        "#{amount} by #{user}"
                    end

                  IO.puts("#{summary.id} | #{summary.product_name} | #{bid_text}")
                end)

              {:error, reason} ->
                IO.puts("Error: #{inspect(reason)}")
            end

            loop(admin_pid)

          ["create", product_name, price_text, duration_text] ->
            case {Integer.parse(price_text), Integer.parse(duration_text)} do
              {{price, ""}, {duration, ""}} ->
                AuctionClient.create_auction(
                  admin_pid,
                  product_name,
                  price,
                  duration
                )

                receive do
                  {:ok, auction_id} ->
                    IO.puts("Created auction #{auction_id}.")

                  {:error, reason} ->
                    IO.puts("Error: #{inspect(reason)}")
                after
                  3_000 ->
                    IO.puts("Error: creation response timed out; outcome unknown.")
                end

              _ ->
                IO.puts("Error: price and duration must be integers.")
            end

            loop(admin_pid)

          ["show", auction_id_text] ->
            case Integer.parse(auction_id_text) do
              {auction_id, ""} ->
                case AuctionClient.consult_auction(admin_pid, auction_id) do
                  {:ok, info} ->
                    IO.inspect(info, label: "Auction", pretty: true)

                  {:error, reason} ->
                    IO.puts("Error: #{inspect(reason)}")
                end

              _ ->
                IO.puts("Error: auction ID must be an integer.")
            end

            loop(admin_pid)

          ["bid", auction_id_text, user, amount_text] ->
            case {Integer.parse(auction_id_text), Integer.parse(amount_text)} do
              {{auction_id, ""}, {amount, ""}} ->
                case AuctionClient.place_bid(admin_pid, auction_id, user, amount) do
                  {:ok, :bid_accepted} ->
                    IO.puts("Bid accepted.")

                  {:error, reason} ->
                    IO.puts("Error: #{inspect(reason)}")
                end

              _ ->
                IO.puts("Error: auction ID and amount must be integers.")
            end

            loop(admin_pid)

          _command ->
            IO.puts("Unknown command. Type help.")
            loop(admin_pid)
        end
    end
  end

  defp split_command(line) do
    line
    |> String.trim()
    |> OptionParser.split()
  rescue
    _error in [ArgumentError, RuntimeError] ->
      :invalid_command
  end
end
