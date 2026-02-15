defmodule VibeWeb.RoomLive do
  use VibeWeb, :live_view

  alias Vibe.YouTube

  @impl true
  def mount(params, _session, socket) do
    me = Map.get(params, "me", "anon")
    room = Map.get(params, "room", "main")
    topic = "room:" <> room

    socket =
      socket
      |> assign(:me, me)
      |> assign(:room, room)
      |> assign(:topic, topic)
      |> assign(:video_visible, true)
      |> assign(:messages, [])
      |> assign(:draft, "")
      |> assign(:search_q, "")
      |> assign(:search_results, [])
      |> assign(:selected, nil)
      |> assign(:current_video_id, nil)
      |> assign(:show_reactions_for, nil)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Vibe.PubSub, topic)
    end

    {:ok, socket}
  end

  # ----------------------------
  # UI EVENTS
  # ----------------------------

  @impl true
  def handle_event("toggle_video", _params, socket) do
    {:noreply, update(socket, :video_visible, &(!&1))}
  end

  # keep draft controlled (recommended)
  @impl true
  def handle_event("draft", %{"draft" => draft}, socket) do
    {:noreply, assign(socket, :draft, draft)}
  end

  # SEND CHAT (broadcast-only, PubSub is source of truth)
  @impl true
  def handle_event("send", %{"draft" => text}, socket) do
    body = String.trim(text || "")

    if body == "" do
      {:noreply, socket}
    else
      msg = %{
        id: System.unique_integer([:positive]),
        user: socket.assigns.me,
        body: body,
        at: DateTime.utc_now(),
        reactions: %{}
      }

      Phoenix.PubSub.broadcast(
        Vibe.PubSub,
        socket.assigns.topic,
        {:chat_msg, msg}
      )

      {:noreply, assign(socket, :draft, "")}
    end
  end

  # ----------------------------
  # REACTIONS
  # ----------------------------

  # Opens/closes picker for a specific message
  @impl true
  def handle_event("open_reactions", %{"msg" => msg_id}, socket) do
    # msg_id comes from HEEx as a string; our msg.id is an integer
    msg_id = parse_int(msg_id)

    show_for =
      if socket.assigns.show_reactions_for == msg_id do
        nil
      else
        msg_id
      end

    {:noreply, assign(socket, :show_reactions_for, show_for)}
  end

  # Broadcast reaction so PubSub remains the source of truth
  @impl true
  def handle_event("react", %{"msg" => msg_id, "emoji" => emoji}, socket) do
    msg_id = parse_int(msg_id)
    emoji = String.slice(to_string(emoji), 0, 8)

    Phoenix.PubSub.broadcast(
      Vibe.PubSub,
      socket.assigns.topic,
      {:chat_react, %{msg_id: msg_id, emoji: emoji}}
    )

    {:noreply, assign(socket, :show_reactions_for, nil)}
  end

  # ----------------------------
  # SEARCH (YOUTUBE)
  # ----------------------------

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    q = String.trim(q || "")

    results =
      if q == "" do
        []
      else
        case YouTube.search(q, 10) do
          {:ok, items} ->
            Enum.map(items, fn v ->
              %{
                id: v.id,
                title: v.title,
                artist: v.artist,
                dur: format_duration(v.duration_s)
              }
            end)

          _ ->
            []
        end
      end

    {:noreply,
    socket
    |> assign(:search_q, q)
    |> assign(:search_results, results)}
  end

  # ----------------------------
  # PICK VIDEO (LOAD FOR BOTH)
  # ----------------------------

  @impl true
  def handle_event("pick", %{"id" => id}, socket) do
    video = Enum.find(socket.assigns.search_results, &(&1.id == id))

    if video do
      payload = %{
        video_id: video.id,
        position_ms: 0,
        is_playing: false,
        sent_at_ms: System.system_time(:millisecond)
      }

      Phoenix.PubSub.broadcast(
        Vibe.PubSub,
        socket.assigns.topic,
        {:player_load, payload}
      )

      {:noreply,
      socket
      |> assign(:selected, video)
      |> assign(:current_video_id, video.id)}
    else
      {:noreply, socket}
    end
  end

  # ----------------------------
  # PLAYER EVENTS (FROM JS)
  # ----------------------------

  @impl true
  def handle_event("player_event", params, socket) do
    payload =
      params
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put_new("video_id", socket.assigns.current_video_id)

    Phoenix.PubSub.broadcast(
      Vibe.PubSub,
      socket.assigns.topic,
      {:player_sync, payload}
    )

    {:noreply, socket}
  end

  # ----------------------------
  # PUBSUB INBOX
  # ----------------------------

  @impl true
  def handle_info({:chat_msg, msg}, socket) do
    {:noreply,
    socket
    |> update(:messages, &(&1 ++ [ensure_reactions(msg)]))
    |> push_event("scroll_chat", %{})}
  end

  @impl true
  def handle_info({:chat_react, %{msg_id: msg_id, emoji: emoji}}, socket) do
    messages =
      Enum.map(socket.assigns.messages, fn m ->
        if m.id == msg_id do
          reactions = Map.update(m.reactions || %{}, emoji, 1, &(&1 + 1))
          %{m | reactions: reactions}
        else
          m
        end
      end)

    {:noreply, assign(socket, :messages, messages)}
  end

  @impl true
  def handle_info({:player_load, payload}, socket) do
    video_id =
      cond do
        is_map(payload) && Map.has_key?(payload, "video_id") -> payload["video_id"]
        is_map(payload) && Map.has_key?(payload, :video_id) -> payload[:video_id]
        true -> nil
      end

    {:noreply,
    socket
    |> assign(:current_video_id, video_id)
    |> push_event("player_load", payload)}
  end

  @impl true
  def handle_info({:player_sync, payload}, socket) do
    {:noreply, push_event(socket, "player_sync", payload)}
  end

  # ----------------------------
  # HELPERS
  # ----------------------------

  defp format_duration(nil), do: "--:--"

  defp format_duration(sec) when is_integer(sec) do
    m = div(sec, 60)
    s = rem(sec, 60)
    "#{m}:#{String.pad_leading(Integer.to_string(s), 2, "0")}"
  end

  defp parse_int(nil), do: nil

  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp ensure_reactions(msg) when is_map(msg) do
    Map.put_new(msg, :reactions, %{})
  end
end
