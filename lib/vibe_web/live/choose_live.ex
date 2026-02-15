alias Phoenix.LiveView.JS

defmodule VibeWeb.ChooseLive do
  use VibeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("pick", %{"me" => me}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/room?me=#{me}&room=main")}
  end
end
