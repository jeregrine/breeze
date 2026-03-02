defmodule Breeze.LogView do
  @moduledoc """
  Built-in implicit module for realtime log viewers.

  `Breeze.LogView` provides keyboard scrolling for log streams and helper
  functions for scrollback and formatting.

  ## Keyboard controls

    * `ArrowUp`/`k` - move to previous entry
    * `ArrowDown`/`j` - move to next entry
    * `PageUp` / `PageDown` - jump by viewport height
    * `Home` / `End` - jump to first/last entry (`End` re-enables follow)
    * `f` - toggle follow mode (enable snaps to tail)

  ## Root options

  Set these on the root implicit box via attributes:

    * `log-follow` - auto-follow tail (`true` by default)
    * `log-scroll-padding` - keep N rows around the current selection
    * `log-max-entries` - keep at most N rendered entries
    * `log-viewport-height` - explicit viewport height override

  Child boxes should include at least `level` and `message` (or `value`) attrs.
  """

  alias Breeze.Viewport

  @level_styles %{
    debug: "text-244",
    info: "text-39",
    warning: "text-214",
    error: "text-196"
  }

  @selected_style "bg-15 text-0 bold"

  @type level :: :debug | :info | :warning | :error

  @type state :: %{
          follow: boolean(),
          offset: non_neg_integer(),
          viewport_height: non_neg_integer(),
          scroll_padding: non_neg_integer(),
          max_entries: non_neg_integer(),
          entries: [map()],
          entry_ids: [term()],
          entry_by_id: %{optional(term()) => map()},
          row_by_id: %{optional(term()) => non_neg_integer()},
          selected_id: term() | nil,
          total_count: non_neg_integer()
        }

  @spec init([map()], map()) :: state()
  def init(children, last_state), do: init(children, %{}, last_state)

  @spec init([map()], map(), map()) :: state()
  def init(children, root_attrs, last_state) do
    follow = bool_option(root_attrs, :"log-follow", Map.get(last_state, :follow, true))

    scroll_padding =
      int_option(root_attrs, :"log-scroll-padding", Map.get(last_state, :scroll_padding, 0))

    max_entries =
      int_option(root_attrs, :"log-max-entries", Map.get(last_state, :max_entries, 1_000))

    viewport_height =
      viewport_height_option(root_attrs, Map.get(last_state, :viewport_height, 0))

    entries =
      children
      |> Enum.with_index()
      |> Enum.map(fn {child, index} -> child_to_entry(child, index) end)
      |> Enum.take(-max_entries)

    state = %{
      follow: follow,
      offset: normalize_int(Map.get(last_state, :offset, 0)),
      viewport_height: viewport_height,
      scroll_padding: scroll_padding,
      max_entries: max_entries,
      entries: entries,
      entry_ids: [],
      selected_id: Map.get(last_state, :selected_id),
      row_by_id: %{},
      entry_by_id: %{},
      total_count: 0
    }

    recompute(state)
  end

  @spec handle_event(term(), map(), state()) :: {:noreply, state()} | {{:change, map()}, state()}
  def handle_event(_, %{"key" => key, "element" => element}, state)
      when key in ["ArrowDown", "j"] do
    state
    |> update_viewport(element)
    |> move_selection_by(1)
    |> reply_change()
  end

  def handle_event(_, %{"key" => key, "element" => element}, state)
      when key in ["ArrowUp", "k"] do
    state
    |> update_viewport(element)
    |> move_selection_by(-1)
    |> reply_change()
  end

  def handle_event(_, %{"key" => "PageDown", "element" => element}, state) do
    jump = max(viewport_height(element) - 1, 1)

    state
    |> update_viewport(element)
    |> move_selection_by(jump)
    |> reply_change()
  end

  def handle_event(_, %{"key" => "PageUp", "element" => element}, state) do
    jump = max(viewport_height(element) - 1, 1)

    state
    |> update_viewport(element)
    |> move_selection_by(-jump)
    |> reply_change()
  end

  def handle_event(_, %{"key" => "Home", "element" => element}, state) do
    state
    |> update_viewport(element)
    |> select_first()
    |> reply_change()
  end

  def handle_event(_, %{"key" => "End", "element" => element}, state) do
    state
    |> update_viewport(element)
    |> select_last(true)
    |> reply_change()
  end

  def handle_event(_, %{"key" => "f", "element" => element}, state) do
    state = update_viewport(state, element)

    state =
      if state.follow do
        %{state | follow: false}
        |> recompute()
      else
        select_last(state, true)
      end

    reply_change(state)
  end

  def handle_event(_, _, state), do: {:noreply, state}

  @spec handle_modifiers(:root | :child, keyword(), state()) :: keyword()
  def handle_modifiers(:root, _flags, state), do: [scroll_y: state.offset]

  def handle_modifiers(:child, flags, state) do
    id = child_id_from_flags(flags)
    level = level_from_map(flags)

    selected? = not is_nil(id) and state.selected_id == id
    level_style = Map.get(@level_styles, level, @level_styles.info)

    base_style = if selected?, do: @selected_style, else: level_style

    []
    |> add_style(base_style)
    |> maybe_add_selected(selected?)
  end

  @doc """
  Keep only the latest `max_entries` entries while appending one entry.
  """
  @spec push([map()], term(), pos_integer()) :: [map()]
  def push(entries, entry, max_entries \\ 1_000)

  def push(nil, entry, max_entries), do: push([], entry, max_entries)

  def push(entries, entry, max_entries) when is_list(entries) and max_entries > 0 do
    entries
    |> Kernel.++([normalize_entry(entry)])
    |> Enum.take(-max_entries)
  end

  @doc """
  Format a log entry for rendering in a single line.

  Accepts binaries, tuples and maps. Maps may include `:timestamp`, `:level`,
  `:message`, `:metadata`, and `:source`.
  """
  @spec format_entry(term(), keyword()) :: binary()
  def format_entry(entry, opts \\ []) do
    entry = normalize_entry(entry)

    include_metadata = Keyword.get(opts, :metadata, false)

    parts =
      []
      |> maybe_push(format_timestamp(entry.timestamp))
      |> maybe_push("[#{entry.level |> Atom.to_string() |> String.upcase()}]")
      |> maybe_push(format_source(entry.source))
      |> maybe_push(entry.message)
      |> maybe_push(if(include_metadata, do: format_metadata(entry.metadata), else: nil))

    parts
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp reply_change(state), do: {{:change, payload(state)}, state}

  defp payload(state) do
    selected = Map.get(state.entry_by_id, state.selected_id)

    %{
      follow: state.follow,
      selected_id: state.selected_id,
      selected_index: selected_index(state),
      offset: state.offset,
      total: state.total_count,
      visible: state.total_count,
      value: selected && selected.value,
      level: selected && selected.level,
      text: selected && selected.text
    }
  end

  defp recompute(state) do
    entries = state.entries

    row_by_id =
      entries
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {entry, row}, acc ->
        Map.put(acc, entry.id, row)
      end)

    entry_by_id = Map.new(entries, &{&1.id, &1})
    entry_ids = Enum.map(entries, & &1.id)

    selected_id =
      cond do
        entry_ids == [] ->
          nil

        state.follow ->
          List.last(entry_ids)

        state.selected_id in entry_ids ->
          state.selected_id

        true ->
          hd(entry_ids)
      end

    total_count = length(entries)

    offset =
      state.offset
      |> clamp_offset(total_count, state.viewport_height)
      |> maybe_follow_tail(state.follow, total_count, state.viewport_height)
      |> maybe_ensure_selected_visible(selected_id, row_by_id, state, total_count)

    %{
      state
      | selected_id: selected_id,
        entry_ids: entry_ids,
        row_by_id: row_by_id,
        entry_by_id: entry_by_id,
        total_count: total_count,
        offset: offset
    }
  end

  defp move_selection_by(%{entry_ids: []} = state, _delta),
    do: %{state | follow: false} |> recompute()

  defp move_selection_by(state, delta) do
    current_index =
      case Enum.find_index(state.entry_ids, &(&1 == state.selected_id)) do
        nil when delta >= 0 -> -1
        nil -> length(state.entry_ids)
        index -> index
      end

    next_index =
      current_index
      |> Kernel.+(delta)
      |> clamp(0, length(state.entry_ids) - 1)

    selected_id = Enum.at(state.entry_ids, next_index)

    %{state | selected_id: selected_id, follow: false}
    |> recompute()
  end

  defp select_first(%{entry_ids: []} = state), do: %{state | follow: false} |> recompute()

  defp select_first(state) do
    %{state | selected_id: hd(state.entry_ids), follow: false}
    |> recompute()
  end

  defp select_last(%{entry_ids: []} = state, follow?) do
    %{state | follow: follow?}
    |> recompute()
  end

  defp select_last(state, follow?) do
    %{state | selected_id: List.last(state.entry_ids), follow: follow?}
    |> recompute()
  end

  defp update_viewport(state, element) when is_map(element) do
    height = viewport_height(element)

    if height > 0 do
      %{state | viewport_height: height}
      |> recompute()
    else
      state
    end
  end

  defp update_viewport(state, _), do: state

  defp maybe_follow_tail(_offset, true, total_count, viewport_height)
       when is_integer(viewport_height) and viewport_height > 0 do
    max(total_count - viewport_height, 0)
  end

  defp maybe_follow_tail(offset, _follow, _total_count, _viewport_height), do: offset

  defp maybe_ensure_selected_visible(offset, selected_id, row_by_id, state, total_count)
       when is_integer(offset) and is_integer(total_count) do
    row = selected_id && Map.get(row_by_id, selected_id)

    cond do
      not is_integer(row) ->
        offset

      state.viewport_height <= 0 ->
        offset

      true ->
        viewport =
          Viewport.from_dimensions(%{
            height: state.viewport_height,
            viewport_height: state.viewport_height,
            content_height: total_count
          })

        Viewport.ensure_row_visible(offset, row, viewport, padding: state.scroll_padding)
    end
  end

  defp selected_index(state) do
    Enum.find_index(state.entry_ids, &(&1 == state.selected_id))
  end

  defp child_to_entry(child, index) do
    message = text_from_map(child)
    value = Map.get(child, :value)

    %{
      id: child_id_from_map(child, index, message),
      level: level_from_map(child),
      text: message,
      value: value
    }
  end

  defp child_id_from_flags(flags) do
    flags
    |> Map.new()
    |> child_id_from_map(0, "")
  end

  defp child_id_from_map(map, index, fallback_text) do
    attr(map, :"log-id") ||
      attr(map, :id) ||
      attr(map, :value) ||
      attr(map, :message) ||
      attr(map, :text) ||
      attr(map, :label) ||
      (fallback_text != "" && fallback_text) ||
      index
  end

  defp text_from_map(map) do
    (attr(map, :message) || attr(map, :text) || attr(map, :label) || attr(map, :value) || "")
    |> to_string()
  end

  defp level_from_map(map), do: normalize_level(attr(map, :level, :info))

  defp normalize_level(level) when level in [:debug, :info, :warning, :error], do: level
  defp normalize_level(:warn), do: :warning
  defp normalize_level(:notice), do: :info
  defp normalize_level(:critical), do: :error

  defp normalize_level(level) when is_binary(level) do
    level
    |> String.downcase()
    |> case do
      "debug" -> :debug
      "info" -> :info
      "notice" -> :info
      "warn" -> :warning
      "warning" -> :warning
      "error" -> :error
      "critical" -> :error
      _ -> :info
    end
  end

  defp normalize_level(_), do: :info

  defp normalize_entry(%{message: _} = entry) do
    message = to_string(Map.get(entry, :message))
    id = entry_id(entry, message)

    %{
      id: id,
      value: Map.get(entry, :value, id),
      timestamp: Map.get(entry, :timestamp),
      level: normalize_level(Map.get(entry, :level, :info)),
      source: Map.get(entry, :source),
      message: message,
      metadata: Map.get(entry, :metadata, %{})
    }
  end

  defp normalize_entry(%{msg: msg} = entry) do
    normalize_entry(%{
      id: Map.get(entry, :id),
      value: Map.get(entry, :value),
      timestamp: Map.get(entry, :timestamp),
      level: Map.get(entry, :level, :info),
      source: Map.get(entry, :source),
      message: msg,
      metadata: Map.get(entry, :metadata, %{})
    })
  end

  defp normalize_entry({level, message}) do
    normalize_entry(%{level: level, message: message, metadata: %{}})
  end

  defp normalize_entry({timestamp, level, message}) do
    normalize_entry(%{timestamp: timestamp, level: level, message: message, metadata: %{}})
  end

  defp normalize_entry(message) when is_binary(message) do
    normalize_entry(%{level: :info, message: message, metadata: %{}})
  end

  defp normalize_entry(other) do
    normalize_entry(%{level: :info, message: inspect(other), metadata: %{}})
  end

  defp entry_id(entry, fallback) do
    Map.get(entry, :id) ||
      Map.get(entry, :"log-id") ||
      Map.get(entry, :value) ||
      fallback
  end

  defp format_timestamp(nil), do: nil

  defp format_timestamp(%DateTime{} = dt) do
    dt
    |> DateTime.to_time()
    |> Time.to_iso8601()
  end

  defp format_timestamp(%NaiveDateTime{} = dt) do
    dt
    |> NaiveDateTime.to_time()
    |> Time.to_iso8601()
  end

  defp format_timestamp({{y, m, d}, {hh, mm, ss}}) do
    "[#{pad2(y)}-#{pad2(m)}-#{pad2(d)} #{pad2(hh)}:#{pad2(mm)}:#{pad2(ss)}]"
  end

  defp format_timestamp(other) when is_binary(other), do: other
  defp format_timestamp(other), do: to_string(other)

  defp format_source(nil), do: nil
  defp format_source(source), do: "(#{source})"

  defp format_metadata(metadata) when metadata in [%{}, []], do: nil
  defp format_metadata(metadata), do: inspect(metadata)

  defp add_style(mods, nil), do: mods
  defp add_style(mods, style), do: mods ++ [style: style]

  defp maybe_add_selected(mods, true), do: mods ++ [selected: true]
  defp maybe_add_selected(mods, false), do: mods

  defp maybe_push(list, nil), do: list
  defp maybe_push(list, ""), do: list
  defp maybe_push(list, val), do: list ++ [val]

  defp clamp_offset(offset, total_count, viewport_height)
       when is_integer(offset) and is_integer(total_count) and is_integer(viewport_height) and
              viewport_height > 0 do
    clamp(offset, 0, max(total_count - viewport_height, 0))
  end

  defp clamp_offset(offset, _total_count, _viewport_height), do: max(offset, 0)

  defp clamp(value, min_value, max_value) do
    value
    |> max(min_value)
    |> min(max_value)
  end

  defp viewport_height(%Viewport{viewport_height: height}) when is_integer(height), do: height

  defp viewport_height(viewport) when is_map(viewport) do
    viewport
    |> Viewport.from_dimensions()
    |> viewport_height()
  end

  defp viewport_height(_), do: 0

  defp attr(data, key, default \\ nil)
  defp attr(data, key, default) when is_map(data), do: Map.get(data, key, default)
  defp attr(data, key, default) when is_list(data), do: Keyword.get(data, key, default)
  defp attr(_data, _key, default), do: default

  defp bool_option(map, key, default) do
    map
    |> Map.get(key)
    |> bool_value(default)
  end

  defp bool_value(value, _default) when value in [true, false], do: value
  defp bool_value("true", _default), do: true
  defp bool_value("false", _default), do: false
  defp bool_value("1", _default), do: true
  defp bool_value("0", _default), do: false
  defp bool_value(nil, default), do: default
  defp bool_value(_, default), do: default

  defp viewport_height_option(root_attrs, default) do
    explicit = Map.get(root_attrs, :"log-viewport-height")

    fallback = infer_height_from_style(root_attrs, default)

    normalize_int(explicit, fallback)
  end

  defp infer_height_from_style(root_attrs, default) do
    style = Map.get(root_attrs, :style, "") |> to_string()

    case Regex.run(~r/(?:^|\s)height-(\d+)(?:\s|$)/, style) do
      [_, value] -> normalize_int(value, default)
      _ -> normalize_int(default, 0)
    end
  end

  defp int_option(map, key, default) do
    map
    |> Map.get(key)
    |> normalize_int(default)
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

  defp pad2(num) when is_integer(num),
    do: num |> Integer.to_string() |> String.pad_leading(2, "0")
end
