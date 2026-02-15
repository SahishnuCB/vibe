defmodule Vibe.YtSuggest do
  @endpoint "https://suggestqueries.google.com/complete/search"

  def fetch(query) do
    url =
      @endpoint <>
        "?" <>
        URI.encode_query(%{client: "firefox", ds: "yt", q: query})

    req = Finch.build(:get, url)

    # IMPORTANT: your app starts Finch with name: Finch
    case Finch.request(req, Finch, receive_timeout: 3_000) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, [_q, suggestions | _]} when is_list(suggestions) ->
            {:ok, Enum.take(suggestions, 8)}

          _ ->
            {:error, :bad_payload}
        end

      _ ->
        {:error, :failed}
    end
  end
end
