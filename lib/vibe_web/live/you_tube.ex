defmodule Vibe.YouTube do
  @search_url "https://www.googleapis.com/youtube/v3/search"
  @videos_url "https://www.googleapis.com/youtube/v3/videos"

  def search(query, max \\ 8) do
    key = api_key!()

    q =
      URI.encode_query(%{
        "part" => "snippet",
        "type" => "video",
        "q" => query,
        "maxResults" => Integer.to_string(max),
        "key" => key
      })

    with {:ok, body1} <- get_json(@search_url <> "?" <> q),
        ids <- extract_video_ids(body1),
        {:ok, dur_map} <- fetch_durations(ids) do
      results =
        (body1["items"] || [])
        |> Enum.map(fn item ->
          id = get_in(item, ["id", "videoId"])
          snip = item["snippet"] || %{}

          %{
            id: id,
            title: snip["title"],
            artist: snip["channelTitle"],
            thumb: get_in(snip, ["thumbnails", "medium", "url"]),
            duration_s: Map.get(dur_map, id)
          }
        end)
        |> Enum.filter(&is_binary(&1.id))

      {:ok, results}
    end
  end

  defp fetch_durations([]), do: {:ok, %{}}

  defp fetch_durations(ids) do
    key = api_key!()

    q =
      URI.encode_query(%{
        "part" => "contentDetails",
        "id" => Enum.join(ids, ","),
        "key" => key
      })

    with {:ok, body} <- get_json(@videos_url <> "?" <> q) do
      m =
        (body["items"] || [])
        |> Enum.reduce(%{}, fn it, acc ->
          id = it["id"]
          dur = get_in(it, ["contentDetails", "duration"])
          Map.put(acc, id, iso8601_duration_to_seconds(dur))
        end)

      {:ok, m}
    end
  end

  defp get_json(url) do
    req = Finch.build(:get, url, [{"accept", "application/json"}])

    case Finch.request(req, Vibe.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_video_ids(body) do
    (body["items"] || [])
    |> Enum.map(&get_in(&1, ["id", "videoId"]))
    |> Enum.filter(&is_binary/1)
  end

  # Example: "PT3M13S"
  defp iso8601_duration_to_seconds(nil), do: nil

  defp iso8601_duration_to_seconds(dur) when is_binary(dur) do
    re = ~r/^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/

    case Regex.run(re, dur) do
      [_, h, m, s] -> to_i(h) * 3600 + to_i(m) * 60 + to_i(s)
      _ -> nil
    end
  end

  defp to_i(nil), do: 0
  defp to_i(""), do: 0
  defp to_i(x), do: String.to_integer(x)

  defp api_key! do
    System.get_env("YOUTUBE_API_KEY") ||
      raise "Missing YOUTUBE_API_KEY environment variable"
  end
end
