defmodule ListViewDemo do
  use Breeze.View

  def mount(_opts, term) do
    {:ok, term |> focus("languages") |> assign(selected: nil)}
  end

  def render(assigns) do
    ~H"""
    <box>
      <.list id="languages" br-change="change">
        <:item value="elixir">Elixir</:item>
        <:item value="erlang">Erlang</:item>
        <:item value="rust">Rust</:item>
        <:item value="go">Go</:item>
        <:item value="zig">Zig</:item>
        <:item value="python">Python</:item>
        <:item value="lua">Lua</:item>
        <:item value="gleam">Gleam</:item>
        <:item value="haskell">Haskell</:item>
      </.list>
      <box :if={@selected} style="border width-24">Selected: <%= @selected %></box>
    </box>
    """
  end

  attr(:id, :string, required: true)
  attr(:rest, :global)

  slot :item do
    attr(:value, :string, required: true)
  end

  def list(assigns) do
    ~H"""
    <box
      id={@id}
      implicit={Breeze.Implicit.List}
      list-loop="true"
      list-scroll-padding="1"
      focusable
      style="border width-24 height-8 overflow-scroll focus:border-3"
      {@rest}
    >
      <box :for={item <- @item} value={item.value} style="selected:bg-4 selected:text-7 width-24">
        <%= render_slot(item, %{}) %>
      </box>
    </box>
    """
  end

  def handle_event("change", %{value: value}, term) do
    {:noreply, assign(term, selected: value)}
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(_, term), do: {:noreply, term}
end

Breeze.Server.start_link(view: ListViewDemo)
:timer.sleep(100_000)
