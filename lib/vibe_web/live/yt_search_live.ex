defmodule VibeWeb.YtSearchLive do
  use VibeWeb, :live_view
  alias Vibe.YtSuggest

  def mount(_params, _session, socket) do
    {:ok, assign(socket, q: "", suggestions: [])}
  end

  def handle_event("suggest", %{"q" => q}, socket) do
    q = String.trim(q)

    suggestions =
      if String.length(q) < 2 do
        []
      else
        case YtSuggest.fetch(q) do
          {:ok, s} -> s
          _ -> []
        end
      end

    {:noreply, assign(socket, q: q, suggestions: suggestions)}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto p-6">
      <h2 class="text-lg font-semibold mb-2">YouTube Search</h2>

      <.form for={%{}} phx-change="suggest">
        <input
          name="q"
          value={@q}
          phx-debounce="250"
          autocomplete="off"
          placeholder="Search…"
          class="w-full border rounded px-3 py-2"
        />
      </.form>

      <ul :if={@suggestions != []} class="mt-2 border rounded">
        <li :for={s <- @suggestions} class="px-3 py-2">
          <%= s %>
        </li>
      </ul>
    </div>
    """
  end
end
