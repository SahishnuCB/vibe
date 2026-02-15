defmodule Vibe.RoomServer do
  use GenServer

  @name __MODULE__

  # --- Public API ---
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: @name)

  def topic(room), do: "vibe:room:" <> room

  def get_state(room), do: GenServer.call(@name, {:get_state, room})

  def add_message(room, msg), do: GenServer.call(@name, {:add_message, room, msg})
  def set_selected(room, selected), do: GenServer.call(@name, {:set_selected, room, selected})
  def set_video_visible(room, visible), do: GenServer.call(@name, {:set_video_visible, room, visible})

  # NEW:
  def set_playback(room, playback), do: GenServer.call(@name, {:set_playback, room, playback})

  # --- Server ---
  @impl true
  def init(_) do
    {:ok, %{rooms: %{}}}
  end

  @impl true
  def handle_call({:get_state, room}, _from, state) do
    room_state = Map.get(state.rooms, room, default_room_state())
    {:reply, room_state, put_in(state.rooms[room], room_state)}
  end

  def handle_call({:add_message, room, msg}, _from, state) do
    rs = Map.get(state.rooms, room, default_room_state())
    msgs = (rs.messages ++ [msg]) |> keep_last(100)
    rs = %{rs | messages: msgs}

    broadcast(room, rs)
    {:reply, :ok, put_in(state.rooms[room], rs)}
  end

  def handle_call({:set_selected, room, selected}, _from, state) do
    rs = Map.get(state.rooms, room, default_room_state())
    rs = %{rs | selected: selected}

    broadcast(room, rs)
    {:reply, :ok, put_in(state.rooms[room], rs)}
  end

  def handle_call({:set_video_visible, room, visible}, _from, state) do
    rs = Map.get(state.rooms, room, default_room_state())
    rs = %{rs | video_visible: visible}

    broadcast(room, rs)
    {:reply, :ok, put_in(state.rooms[room], rs)}
  end

  # NEW: last action wins
  def handle_call({:set_playback, room, playback}, _from, state) do
    rs = Map.get(state.rooms, room, default_room_state())
    rs = %{rs | playback: playback}

    broadcast(room, rs)
    {:reply, :ok, put_in(state.rooms[room], rs)}
  end

  defp broadcast(room, rs) do
    Phoenix.PubSub.broadcast(Vibe.PubSub, topic(room), {:room_state, room, rs})
  end

  defp default_room_state do
    %{
      messages: [],
      selected: nil,
      video_visible: true,
      # playback is authoritative state
      playback: %{
        video_id: nil,
        is_playing: false,
        position_ms: 0,
        sent_at_ms: System.system_time(:millisecond)
      }
    }
  end

  defp keep_last(list, n) do
    len = length(list)
    if len <= n, do: list, else: Enum.drop(list, len - n)
  end
end
