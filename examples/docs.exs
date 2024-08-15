defmodule Breeze.List do
  def init(children, last_state) do
    values =
      children
      |> Enum.filter(&Map.has_key?(&1, :value))
      |> Enum.map(&(&1.value))

    width =
      children
      |> Enum.find_value(fn c -> Map.get(c, :"list-width") end)
      |> then(fn
        nil -> last_state[:width] || 32
        w -> String.to_integer(w)
      end)

    %{
      values: values,
      selected: last_state[:selected],
      offset: last_state[:offset] || 0,
      length: length(values),
      wrap: last_state[:wrap] || false,
      width: width
    }
  end

  def handle_event(_, %{"key" => "w"}, state) do
    new_wrap = !state.wrap
    iw = inner_width(state.width)

    offset =
      if new_wrap do
        rows_before(state.values, state.offset, iw)
      else
        item_index_at_row(state.values, state.offset, iw)
      end

    {:noreply, %{state | wrap: new_wrap, offset: offset}}
  end

  def handle_event(_, %{"key" => "ArrowDown", "element" => element}, %{wrap: true} = state) do
    iw = inner_width(state.width)
    index = Enum.find_index(state.values, &(&1 == state.selected))
    last_index = state.length - 1

    {new_index, offset} =
      cond do
        is_nil(index) -> {0, 0}
        index >= last_index -> {0, 0}
        true ->
          ni = index + 1
          {ni, scroll_to(state.values, ni, state.offset, element.viewport_height, iw)}
      end

    new_value = Enum.at(state.values, new_index)
    {{:change, %{offset: offset, index: new_index, value: new_value}}, %{state | selected: new_value, offset: offset}}
  end

  def handle_event(_, %{"key" => "ArrowDown", "element" => element}, %{offset: offset, values: values} = state) do
    index = Enum.find_index(values, &(&1 == state.selected))
    value = if index, do: Enum.at(values, index + 1) || :reset, else: :reset
    offset = offset_calc(:down, offset, index, element)
    {value, offset} = if value == :reset, do: {hd(values), 0}, else: {value, offset}
    index = Enum.find_index(values, &(&1 == value))
    {{:change, %{offset: offset, index: index, value: value}}, %{state | selected: value, offset: offset}}
  end

  def handle_event(_, %{"key" => "ArrowUp", "element" => element}, %{wrap: true} = state) do
    iw = inner_width(state.width)
    index = Enum.find_index(state.values, &(&1 == state.selected))
    last_index = state.length - 1

    {new_index, offset} =
      cond do
        is_nil(index) || index == 0 ->
          total_rows = rows_before(state.values, state.length, iw)
          {last_index, max(0, total_rows - element.viewport_height)}

        true ->
          ni = index - 1
          {ni, scroll_to(state.values, ni, state.offset, element.viewport_height, iw)}
      end

    new_value = Enum.at(state.values, new_index)
    {{:change, %{offset: offset, index: new_index, value: new_value}}, %{state | selected: new_value, offset: offset}}
  end

  def handle_event(_, %{"key" => "ArrowUp", "element" => element}, %{offset: offset, values: values} = state) do
    index = Enum.find_index(values, &(&1 == state.selected))
    first = hd(Enum.reverse(values))
    value = if index, do: Enum.at(values, index - 1) || first, else: first
    offset = if value == first, do: max(length(values) - element.viewport_height, 0), else: offset_calc(:up, offset, index, element)
    index = Enum.find_index(values, &(&1 == value))
    {{:change, %{offset: offset, index: index, value: value}}, %{state | selected: value, offset: offset}}
  end

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:child, flags, state) do
    overflow = if state.wrap, do: [], else: [style: "overflow-hidden"]

    if state.selected == Keyword.get(flags, :value) do
      [selected: true] ++ overflow
    else
      overflow
    end
  end

  def handle_modifiers(:root, flags, state) do
    [style: "offset-top-#{state.offset}"]
  end

  defp inner_width(width), do: width

  defp item_rows(value, iw) do
    len = String.length(value)
    max(1, div(len + iw - 1, iw))
  end

  defp rows_before(values, index, iw) do
    values |> Enum.take(index) |> Enum.reduce(0, fn v, acc -> acc + item_rows(v, iw) end)
  end

  defp item_index_at_row(values, row, iw) do
    {_, idx} =
      Enum.reduce_while(values, {0, 0}, fn v, {cur_row, idx} ->
        next_row = cur_row + item_rows(v, iw)
        if next_row > row, do: {:halt, {cur_row, idx}}, else: {:cont, {next_row, idx + 1}}
      end)

    idx
  end

  defp scroll_to(values, index, offset, viewport_height, iw) do
    item_start = rows_before(values, index, iw)
    item_end = item_start + item_rows(Enum.at(values, index), iw) - 1

    cond do
      item_start < offset -> item_start
      item_end >= offset + viewport_height -> item_end - viewport_height + 1
      true -> offset
    end
  end

  defp offset_calc(:down, offset, index, element) do
    offset =
      if index && index > (element.viewport_height - clamp()) && index <= element.content_height - clamp() - 1 && offset - index < clamp() do
        offset + 1
      else
        offset
      end

    max(0, min(offset, element.content_height - element.viewport_height))
  end

  defp offset_calc(:up, offset, index, element) do
    offset =
      if index > 0 && (element.viewport_height + index - clamp() + 2 >= element.content_height) && offset - index < clamp() do
        offset
      else
        offset - 1
      end

    max(offset, 0)
  end

  defp clamp(), do: 4
end



defmodule Docs do
  use Breeze.View

  def mount(_opts, term) do
    {:ok, docs} = :application.get_key(:phoenix, :modules)
    # {:ok, docs} = :application.get_key(:termite, :modules)

    term =
      term
      |> focus("docs")
      |> assign(docs: docs, functions: nil, selected: nil, mod_total: length(docs), mod_index: 0, mod_offset: 0, fun_offset: 0, fun_total: 0, fun_index: 0, mod_width: 32, fun_width: 32)

    {:ok, term}
  end

  def render(assigns) do
    ~H"""
    <box style="inline">
      <.list id="docs" br-change="change" index={@mod_index} total={@mod_total} offset={@mod_offset} width={@mod_width}>
      <:item :for={doc <- @docs} value={inspect(doc)}><%= inspect(doc) %></:item>
      </.list>
      <.list id="functions" br-change="function" :if={@selected} index={@fun_index} total={@fun_total} offset={@fun_offset} width={@fun_width}>
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
    <box focusable style={"border height-screen overflow-hidden width-#{@width} focus:border-3"} implicit={Breeze.List} id={@id} {@rest}>
        <box style="absolute left-2 top-0"><%= @index + 1 %>/<%= @total %> (Offset: <%= @offset %>)</box>
        <box
          :for={item <- @item}
          value={item.value}
          list-width={@width}
          style={"selected:bg-24 selected:text-0 focus:selected:text-7 focus:selected:bg-4 width-#{@width}"}
        ><%= render_slot(item, %{}) %></box>
    </box>
    """
  end

  def handle_info(_, term) do
    {:noreply, term}
  end

  def handle_event("change", %{value: value, index: index, offset: offset}, term) do
    term =
      case Code.fetch_docs(String.to_existing_atom("Elixir." <> value)) do
        {:docs_v1, _, :elixir, _, _, _, props} ->
          funs =
          Enum.reduce(props, [], fn prop, acc ->
            head = elem(prop, 0)
            case head do
              {:function, fun, arity} -> ["#{fun}/#{arity}" | acc]
              _ -> acc
            end
          end)

          assign(term, functions: Enum.reverse(funs), selected: value, fun_total: length(funs), mod_index: index, mod_offset: offset)

        _ -> term
      end

    {:noreply, term}
  end

  def handle_event("function", %{value: value, index: index, offset: offset}, term) do
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
