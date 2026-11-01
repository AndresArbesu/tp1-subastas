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
        case String.trim(line) do
          "help" ->
            IO.puts("Commands: help, active, exit")
            loop(admin_pid)

          "exit" ->
            :ok

          "" ->
            loop(admin_pid)

          "active" ->
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


          _command ->
            IO.puts("Unknown command. Type help.")
            loop(admin_pid)
        end
    end
  end
end
