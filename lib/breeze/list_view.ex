defmodule Breeze.ListView do
  @moduledoc """
  Built-in implicit module for keyboard-navigable list views.

  ## Root options

  Set these on the root implicit box via attributes:

    * `list-loop` - wrap selection at edges (`true` by default)
    * `list-scroll-padding` - keep N rows of breathing room around selection
    * `list-selected` - initial selected value
    * `list-initial-index` - initial selected index

  Child boxes should define a `value` attribute.
  """

  alias Breeze.Viewport

  @type state :: %{
          values: list(),
          selected: term() | nil,
          selected_index: non_neg_integer() | nil,
          offset: non_neg_integer(),
          loop: boolean(),
          scroll_padding: non_neg_integer()
        }

  @spec init(list(map()), map()) :: state()
  def init(children, last_state), do: init(children, %{}, last_state)

  @spec init(list(map()), map(), map()) :: state()
  def init(children, root_attrs, last_state) do
    values =
      children
      |> Enum.filter(&Map.has_key?(&1, :value))
      |> Enum.map(& &1.value)

    loop = bool_option(root_attrs, :"list-loop", Map.get(last_state, :loop, true))

    scroll_padding =
      int_option(root_attrs, :"list-scroll-padding", Map.get(last_state, :scroll_padding, 0))

    selected_index =
      values
      |> pick_selected_index(last_state, root_attrs)
      |> normalize_selected_index(values)

    selected = if selected_index, do: Enum.at(values, selected_index), else: nil

    %{
      values: values,
      selected: selected,
      selected_index: selected_index,
      offset: normalize_int(Map.get(last_state, :offset, 0)),
      loop: loop,
      scroll_padding: scroll_padding
    }
  end

  @spec handle_event(term(), map(), state()) :: {:noreply, state()} | {{:change, map()}, state()}
  def handle_event(_, %{"key" => key, "element" => element}, state)
      when key in ["ArrowDown", "j"] do
    state
    |> move_selection(1, element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => key, "element" => element}, state)
      when key in ["ArrowUp", "k"] do
    state
    |> move_selection(-1, element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => "Home", "element" => element}, state) do
    state
    |> set_selection(0, element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => "End", "element" => element}, state) do
    index = max(length(state.values) - 1, 0)

    state
    |> set_selection(index, element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => "PageDown", "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    jump = max(viewport.viewport_height - 1, 1)
    index = (state.selected_index || 0) + jump

    state
    |> set_selection(index, element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => "PageUp", "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    jump = max(viewport.viewport_height - 1, 1)
    index = (state.selected_index || 0) - jump

    state
    |> set_selection(index, element)
    |> maybe_change()
  end

  def handle_event(_, _, state), do: {:noreply, state}

  @spec handle_modifiers(:root | :child, keyword(), state()) :: keyword()
  def handle_modifiers(:root, _flags, state), do: [scroll_y: state.offset]

  def handle_modifiers(:child, flags, state) do
    if state.selected == Keyword.get(flags, :value), do: [selected: true], else: []
  end

  defp move_selection(%{values: []} = state, _delta, _element), do: state

  defp move_selection(state, delta, element) do
    index =
      state
      |> next_index(delta)
      |> normalize_selected_index(state.values)

    set_selection(state, index, element)
  end

  defp set_selection(%{values: []} = state, _index, _element), do: state

  defp set_selection(state, index, element) do
    values = state.values
    index = normalize_selected_index(index, values)

    selected = if index, do: Enum.at(values, index), else: nil

    viewport = Viewport.from_dimensions(element)

    offset =
      if index do
        Viewport.ensure_row_visible(
          state.offset,
          index,
          viewport,
          padding: state.scroll_padding
        )
      else
        Viewport.clamp_scroll_y(state.offset, viewport)
      end

    %{state | selected_index: index, selected: selected, offset: offset}
  end

  defp maybe_change(state) do
    payload = %{
      value: state.selected,
      index: state.selected_index,
      offset: state.offset
    }

    {{:change, payload}, state}
  end

  defp next_index(%{selected_index: nil}, delta) when delta >= 0, do: 0
  defp next_index(%{selected_index: nil, values: values}, _delta), do: max(length(values) - 1, 0)

  defp next_index(%{selected_index: selected_index, values: values, loop: loop?}, delta) do
    max_index = max(length(values) - 1, 0)
    next = selected_index + delta

    cond do
      loop? && next > max_index -> 0
      loop? && next < 0 -> max_index
      true -> next
    end
  end

  defp pick_selected_index(values, last_state, root_attrs) do
    selected = Map.get(last_state, :selected)

    cond do
      selected && Enum.member?(values, selected) ->
        Enum.find_index(values, &(&1 == selected))

      match?(i when is_integer(i), Map.get(last_state, :selected_index)) ->
        Map.get(last_state, :selected_index)

      selected = Map.get(root_attrs, :"list-selected") ->
        Enum.find_index(values, &(&1 == selected))

      true ->
        int_option(root_attrs, :"list-initial-index", 0)
    end
  end

  defp normalize_selected_index(_index, []), do: nil

  defp normalize_selected_index(index, values) when is_integer(index) do
    max_index = length(values) - 1

    index
    |> max(0)
    |> min(max_index)
  end

  defp normalize_selected_index(_index, _values), do: nil

  defp int_option(attrs, key, default) do
    attrs
    |> Map.get(key)
    |> normalize_int(default)
  end

  defp bool_option(attrs, key, default) do
    case Map.get(attrs, key) do
      true -> true
      false -> false
      "true" -> true
      "false" -> false
      "1" -> true
      "0" -> false
      nil -> default
      _ -> default
    end
  end

  defp normalize_int(value, default \\ 0)
  defp normalize_int(value, _default) when is_integer(value), do: max(value, 0)

  defp normalize_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {value, ""} -> max(value, 0)
      _ -> max(default, 0)
    end
  end

  defp normalize_int(_value, default), do: max(default, 0)
end
