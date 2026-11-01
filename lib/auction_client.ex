defmodule AuctionClient do
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

  def place_bid(admin_pid, auction_id, user, amount) do
    case resolve_auction(admin_pid, auction_id) do
      {:ok, auction_pid} ->
        Auction.place_bid(auction_pid, user, amount)

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
