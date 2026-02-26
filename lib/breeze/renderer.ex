defmodule Breeze.Renderer do
  @moduledoc false

  alias BackBreeze.Box

  def render_to_string(mod, assigns, opts \\ []) do
    {_, %{content: content}} = render(mod, assigns, opts)
    content
  end

  def render(mod, assigns, opts \\ []) do
    [{_tag, _, root_children}] =
      mod.render(assigns)
      |> Breeze.Template.render_to_tree(assigns)

    {acc, box} = build_from_tree_nodes(root_children, opts)

    %{box: box, dimensions: dimensions} =
      BackBreeze.Box.render_with_dimensions(box)

    {Map.put(acc, :dimensions, dimensions), box}
  end

  defp build_from_tree_nodes(children, opts) do
    {acc, box} =
      build_tree(children, %BackBreeze.Box{}, [], "", [],
                 %{focusables: [], id: 0, elements: %{}, ids: [], flags: []}, opts)

    acc = %{acc | elements: Map.put(acc.elements, acc.id, acc.flags)}
    ids = Enum.reverse(acc.ids)
    focusables = Enum.reverse(acc.focusables) |> then(&Enum.filter(ids, fn id -> id in &1 end))
    {%{acc | ids: ids, focusables: focusables}, box}
  end

  defp build_tree(
         [{:attribute, ["style", style]} | rest],
         box,
         children,
         _style,
         flags,
         acc,
         opts
       ) do
    build_tree(rest, box, children, style, flags, acc, opts)
  end

  defp build_tree([{:attribute, ["id", box_id]} | rest], box, children, style, flags, acc, opts) do
    ids = [box_id | acc.ids]
    acc = %{acc | ids: ids, flags: Keyword.put(acc.flags, :id, box_id)}
    build_tree(rest, box, children, style, Keyword.put(flags, :id, box_id), acc, opts)
  end

  defp build_tree(
         [{:attribute, ["implicit", mod]} | rest],
         box,
         children,
         style,
         flags,
         acc,
         opts
       ) do
    mod = String.to_atom(mod)
    acc = %{acc | flags: Keyword.put(acc.flags, :implicit, mod)}
    build_tree(rest, box, children, style, Keyword.put(flags, :implicit, mod), acc, opts)
  end

  defp build_tree([{:attribute, [flag, value]} | rest], box, children, style, flags, acc, opts) do
    flag = String.to_atom(flag)
    acc = %{acc | flags: Keyword.put(acc.flags, flag, value)}
    build_tree(rest, box, children, style, Keyword.put(flags, flag, value), acc, opts)
  end

  defp build_tree([{:attribute_bool, [attr]} | rest], box, children, style, flags, acc, opts) do
    {flags, acc} =
      case attr do
        "focusable" ->
          {Keyword.put(flags, :focusable, true),
           %{acc | flags: Keyword.put(acc.flags, :focusable, true)}}

        _ ->
          {flags, acc}
      end

    build_tree(rest, box, children, style, flags, acc, opts)
  end

  defp build_tree([content | rest], box, children, style, flags, acc, opts)
       when is_binary(content) do
    box = %{box | content: String.trim_trailing(content, "\n  ")}
    build_tree(rest, box, children, style, flags, acc, opts)
  end

  defp build_tree([{:box, _, nodes} | rest], box, children, style, flags, acc, opts) do
    child_flags =
      if Keyword.get(flags, :implicit) do
        [implicit_id: Keyword.fetch!(flags, :id)]
      else
        []
      end

    acc = %{
      acc
      | flags: child_flags,
        id: acc.id + 1,
        elements: Map.put(acc.elements, acc.id, acc.flags)
    }

    {acc, child} = build_tree(nodes, %BackBreeze.Box{}, [], "", child_flags, acc, opts)
    build_tree(rest, box, [child | children], style, flags, acc, opts)
  end

  defp build_tree([], box, children, style, flags, acc, opts) do
    %{focusables: focusables} = acc

    focused =
      (Keyword.get(flags, :id) || Keyword.get(flags, :implicit_id)) == Keyword.get(opts, :focused)

    flags = if focused, do: Keyword.put(flags, :focused, focused), else: flags

    style_flags =
      if focused do
        [focus: true]
      else
        []
      end

    implicit_state = Keyword.get(opts, :implicit_state, %{})
    implicit_id = Keyword.get(flags, :implicit_id)
    id = implicit_id || Keyword.get(flags, :id)

    {implicit_mod, implicit} =
      case id && get_in(implicit_state, [id]) do
        nil -> {nil, nil}
        {mod, state} -> {mod, state}
      end

    type = if id == Keyword.get(flags, :id), do: :root, else: :child

    {style_flags, style_modifiers, scroll_modifier} =
      if implicit do
        modifiers = implicit_mod.handle_modifiers(type, flags, implicit)
        parse_modifiers(modifiers, style_flags)
      else
        {style_flags, [], %{top: nil, left: nil}}
      end

    focusables =
      if Keyword.get(flags, :focusable),
        do: [Keyword.get(flags, :id) | focusables],
        else: focusables

    element = string_to_styles(append_style_modifiers(style, style_modifiers), style_flags)

    opts =
      element.attributes
      |> merge_scroll_modifier(scroll_modifier)
      |> Map.put(:style, element.style)

    children = Enum.reverse(children)
    content = box.content
    acc = %{acc | focusables: focusables}
    {acc, %{Box.new(opts) | children: children, content: content}}
  end

  defp parse_modifiers(modifiers, style_flags) when is_list(modifiers) do
    {style_flags, style_modifiers, scroll_modifier} =
      Enum.reduce(modifiers, {style_flags, [], %{top: nil, left: nil}}, fn
        {:style, value}, {flags, styles, scroll} when is_binary(value) ->
          {flags, [value | styles], scroll}

        {:scroll_y, top}, {flags, styles, scroll} when is_integer(top) ->
          {flags, styles, %{scroll | top: top}}

        {:scroll_x, left}, {flags, styles, scroll} when is_integer(left) ->
          {flags, styles, %{scroll | left: left}}

        {:scroll, {top, left}}, {flags, styles, _scroll}
        when is_integer(top) and is_integer(left) ->
          {flags, styles, %{top: top, left: left}}

        {flag, value}, {flags, styles, scroll} when is_atom(flag) ->
          {Keyword.put(flags, flag, value), styles, scroll}

        _, acc ->
          acc
      end)

    {style_flags, Enum.reverse(style_modifiers), scroll_modifier}
  end

  defp parse_modifiers(_modifiers, style_flags),
    do: {style_flags, [], %{top: nil, left: nil}}

  defp append_style_modifiers(style, []), do: style

  defp append_style_modifiers(style, modifiers) do
    [style | modifiers]
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp merge_scroll_modifier(attributes, %{top: nil, left: nil}), do: attributes

  defp merge_scroll_modifier(attributes, %{top: top, left: left}) do
    {existing_top, existing_left} = Map.get(attributes, :scroll, {0, 0})

    top = if is_integer(top), do: max(top, 0), else: existing_top
    left = if is_integer(left), do: max(left, 0), else: existing_left

    Map.put(attributes, :scroll, {top, left})
  end

  defp string_to_styles(str, opts) do
    str =
      case Keyword.get_values(opts, :style) do
        [] -> str
        other -> str <> " " <> Enum.join(other, " ")
      end

    map =
      String.split(str, " ")
      |> Enum.map(&String.split(&1, ":"))
      |> Enum.sort_by(&length/1)
      |> Enum.reduce(%{}, fn style, acc ->
        style =
          Enum.reduce_while(style, nil, fn
            "focus", _ -> if Keyword.get(opts, :focus), do: {:cont, nil}, else: {:halt, nil}
            "selected", _ -> if Keyword.get(opts, :selected), do: {:cont, nil}, else: {:halt, nil}
            other, _ -> {:halt, other}
          end)

        apply_style(style, acc)
      end)

    style_keys = Map.keys(Map.from_struct(%BackBreeze.Style{}))
    {style, attributes} = Map.split(map, style_keys)
    struct(Breeze.Element, %{style: style, attributes: attributes})
  end

  defp apply_style("border", acc), do: Map.put(acc, :border, :line)
  defp apply_style("bold", acc), do: Map.put(acc, :bold, true)
  defp apply_style("italic", acc), do: Map.put(acc, :italic, true)
  defp apply_style("inverse", acc), do: Map.put(acc, :reverse, true)
  defp apply_style("reverse", acc), do: Map.put(acc, :reverse, true)
  defp apply_style("inline", acc), do: Map.put(acc, :display, :inline)

  defp apply_style("overflow-scroll", acc),
    do: Map.merge(acc, %{overflow: :hidden, scrollbar: true})

  defp apply_style("overflow-" <> overflow, acc),
    do: Map.put(acc, :overflow, String.to_existing_atom(overflow))

  defp apply_style("offset-top-" <> num, acc) do
    {_, left} = Map.get(acc, :scroll, {0, 0})
    Map.put(acc, :scroll, {String.to_integer(num), left})
  end

  defp apply_style("offset-left-" <> num, acc) do
    {top, _} = Map.get(acc, :scroll, {0, 0})
    Map.put(acc, :scroll, {top, String.to_integer(num)})
  end

  defp apply_style("absolute", acc), do: Map.put(acc, :position, :absolute)
  defp apply_style("left-" <> num, acc), do: Map.put(acc, :left, String.to_integer(num))
  defp apply_style("top-" <> num, acc), do: Map.put(acc, :top, String.to_integer(num))
  defp apply_style("width-auto", acc), do: Map.put(acc, :width, :auto)
  defp apply_style("width-screen", acc), do: Map.put(acc, :width, :screen)
  defp apply_style("width-" <> num, acc), do: Map.put(acc, :width, String.to_integer(num))
  defp apply_style("height-auto", acc), do: Map.put(acc, :height, :auto)
  defp apply_style("height-screen", acc), do: Map.put(acc, :height, :screen)
  defp apply_style("height-" <> num, acc), do: Map.put(acc, :height, String.to_integer(num))

  defp apply_style("text-" <> num, acc),
    do: Map.put(acc, :foreground_color, String.to_integer(num))

  defp apply_style("bg-" <> num, acc), do: Map.put(acc, :background_color, String.to_integer(num))
  defp apply_style("border-" <> num, acc), do: Map.put(acc, :border_color, String.to_integer(num))
  defp apply_style(_, acc), do: acc
end
