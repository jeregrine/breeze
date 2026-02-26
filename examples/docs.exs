defmodule Docs do
  use Breeze.View

  def mount(_opts, term) do
    {:ok, docs} = :application.get_key(:kernel, :modules)

    term =
      term
      |> focus("docs")
      |> assign(
        docs: docs,
        functions: nil,
        selected: nil,
        mod_total: length(docs),
        mod_index: 0,
        mod_offset: 0,
        fun_offset: 0,
        fun_total: 0,
        fun_index: 0,
        mod_width: 32,
        fun_width: 32
      )

    {:ok, term}
  end

  def render(assigns) do
    ~H"""
    <box style="inline">
      <.list
        id="docs"
        br-change="change"
        index={@mod_index}
        total={@mod_total}
        offset={@mod_offset}
        width={@mod_width}
      >
        <:item :for={doc <- @docs} value={inspect(doc)}><%= inspect(doc) %></:item>
      </.list>
      <.list
        :if={@selected}
        id="functions"
        br-change="function"
        index={@fun_index}
        total={@fun_total}
        offset={@fun_offset}
        width={@fun_width}
      >
        <:item :for={function <- @functions} value={function}><%= function %></:item>
      </.list>
    </box>
    """
  end

  attr(:id, :string, required: true)
  attr(:rest, :global)
  attr(:index, :integer)
  attr(:total, :integer)
  attr(:offset, :integer)
  attr(:width, :integer, default: 32)

  slot :item do
    attr(:value, :string, required: true)
  end

  def list(assigns) do
    ~H"""
    <box
      focusable
      style={"border height-screen overflow-scroll width-#{@width} focus:border-3"}
      implicit={Breeze.ListView}
      id={@id}
      list-width={@width}
      {@rest}
    >
      <box style="absolute left-2 top-0">
        <%= @index + 1 %>
        /
        <%= @total %>
         (Offset: 
        <%= @offset %>
        )
      </box>
      <box
        :for={item <- @item}
        value={item.value}
        style={"selected:bg-24 selected:text-0 focus:selected:text-7 focus:selected:bg-4 width-#{@width}"}
      >
        <%= render_slot(item, %{}) %>
      </box>
    </box>
    """
  end

  def handle_info(_, term) do
    {:noreply, term}
  end

  def handle_event("change", %{value: value, index: index, offset: offset}, term) do
    module =
      case value do
        ":" <> mod -> String.to_existing_atom(mod)
        _ -> String.to_existing_atom("Elixir." <> value)
      end

    term =
      case Code.fetch_docs(module) do
        {:docs_v1, _, lang, _, _, _, props} when lang in [:erlang, :elixir] ->
          funs =
            Enum.reduce(props, [], fn prop, acc ->
              head = elem(prop, 0)

              case head do
                {:function, fun, arity} -> ["#{fun}/#{arity}" | acc]
                _ -> acc
              end
            end)

          assign(term,
            functions: Enum.reverse(funs),
            selected: value,
            fun_total: length(funs),
            mod_index: index,
            mod_offset: offset
          )

        _ ->
          term
      end

    {:noreply, term}
  end

  def handle_event("function", %{index: index, offset: offset}, term) do
    term = assign(term, fun_index: index, fun_offset: offset)
    {:noreply, term}
  end

  def handle_event(_, %{"key" => "+"}, term) do
    term =
      case term.focused do
        "docs" -> assign(term, mod_width: term.assigns.mod_width + 1)
        "functions" -> assign(term, fun_width: term.assigns.fun_width + 1)
        _ -> term
      end

    {:noreply, term}
  end

  def handle_event(_, %{"key" => "-"}, term) do
    term =
      case term.focused do
        "docs" -> assign(term, mod_width: max(10, term.assigns.mod_width - 1))
        "functions" -> assign(term, fun_width: max(10, term.assigns.fun_width - 1))
        _ -> term
      end

    {:noreply, term}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end

Breeze.Server.start_link(view: Docs)
:timer.sleep(100_000)
