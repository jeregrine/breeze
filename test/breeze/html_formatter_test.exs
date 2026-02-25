defmodule Breeze.HTMLFormatterTest do
  use ExUnit.Case, async: true

  alias Breeze.HTMLFormatter

  test "formats nested elements and interpolation" do
    source = "<box><box style=\"bold\">Hello {@name}</box></box>"

    assert HTMLFormatter.format(source, sigil: :H, opening_delimiter: "\"\"\"") ==
             """
             <box>
               <box style="bold">Hello {@name}</box>
             </box>
             """
  end

  test "wraps attributes when a line is too long" do
    source = "<.panel id={@id} class=\"foo bar baz\" br-change=\"change\" />"

    assert HTMLFormatter.format(source,
             sigil: :H,
             opening_delimiter: "\"\"\"",
             line_length: 30
           ) ==
             """
             <.panel
               id={@id}
               class="foo bar baz"
               br-change="change"
             />
             """
  end

  test "keeps :for/:if directives and assign syntax" do
    source = "<box :for={item <- @items} :if={@enabled}>{item.value}</box>"

    assert HTMLFormatter.format(source, sigil: :H, opening_delimiter: "\"\"\"") ==
             """
             <box :for={item <- @items} :if={@enabled}>{item.value}</box>
             """
  end

  test "supports ~H\"...\" noformat modifier" do
    source = "<box><box>{@name}</box></box>"
    assert HTMLFormatter.format(source, sigil: :H, modifiers: ~c"noformat") == source
  end
end
