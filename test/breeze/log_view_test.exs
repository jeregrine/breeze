defmodule Breeze.LogViewTest do
  use ExUnit.Case, async: true

  alias Breeze.LogView
  alias Breeze.Viewport

  defp sample_children do
    [
      %{:"log-id" => "l1", level: "info", message: "boot complete"},
      %{:"log-id" => "l2", level: "warning", message: "slow query"},
      %{:"log-id" => "l3", level: "error", message: "database timeout"},
      %{:"log-id" => "l4", level: "debug", message: "trace packet"}
    ]
  end

  describe "init/3" do
    test "defaults to follow mode and selects tail" do
      state = LogView.init(sample_children(), %{}, %{})

      assert state.follow == true
      assert state.selected_id == "l4"
      assert state.total_count == 4
    end

    test "follows tail when viewport is known" do
      last = %{viewport_height: 2, follow: true}

      state = LogView.init(sample_children(), %{}, last)

      assert state.offset == 2
      assert state.selected_id == "l4"
      assert state.total_count == 4
    end

    test "infers viewport height from style classes" do
      state =
        LogView.init(
          sample_children(),
          %{style: "border width-screen height-2 overflow-scroll"},
          %{}
        )

      assert state.viewport_height == 2
      assert state.offset == 2
      assert state.selected_id == "l4"
    end

    test "follow mode prefers tail over previous selected_id" do
      last = %{follow: true, selected_id: "l1"}

      state = LogView.init(sample_children(), %{}, last)

      assert state.selected_id == "l4"
    end

    test "respects log-max-entries" do
      state = LogView.init(sample_children(), %{:"log-max-entries" => "2"}, %{})

      assert state.total_count == 2
      assert state.entry_ids == ["l3", "l4"]
      assert state.selected_id == "l4"
    end
  end

  describe "handle_event/3" do
    test "moves selection with arrow keys" do
      state = LogView.init(sample_children(), %{}, %{})
      viewport = Viewport.from_dimensions(%{height: 2, viewport_height: 2, content_height: 4})

      {{:change, _payload}, state} =
        LogView.handle_event(:ignore, %{"key" => "ArrowUp", "element" => viewport}, state)

      assert state.selected_id == "l3"
      assert state.follow == false
    end

    test "home/end jump to boundaries" do
      state = LogView.init(sample_children(), %{}, %{})
      viewport = Viewport.from_dimensions(%{height: 2, viewport_height: 2, content_height: 4})

      {{:change, _payload}, state} =
        LogView.handle_event(:ignore, %{"key" => "Home", "element" => viewport}, state)

      assert state.selected_id == "l1"
      assert state.follow == false

      {{:change, _payload}, state} =
        LogView.handle_event(:ignore, %{"key" => "End", "element" => viewport}, state)

      assert state.selected_id == "l4"
      assert state.follow == true
    end

    test "page up/down jumps by viewport size" do
      state = LogView.init(sample_children(), %{}, %{})
      viewport = Viewport.from_dimensions(%{height: 3, viewport_height: 3, content_height: 4})

      {{:change, _payload}, state} =
        LogView.handle_event(:ignore, %{"key" => "PageUp", "element" => viewport}, state)

      assert state.selected_id == "l2"

      {{:change, _payload}, state} =
        LogView.handle_event(:ignore, %{"key" => "PageDown", "element" => viewport}, state)

      assert state.selected_id == "l4"
    end

    test "f toggles follow mode and snaps to tail when enabling" do
      state = LogView.init(sample_children(), %{}, %{})
      viewport = Viewport.from_dimensions(%{height: 2, viewport_height: 2, content_height: 4})

      {{:change, _payload}, state} =
        LogView.handle_event(:ignore, %{"key" => "ArrowUp", "element" => viewport}, state)

      assert state.follow == false
      assert state.selected_id == "l3"

      {{:change, _payload}, state} =
        LogView.handle_event(:ignore, %{"key" => "f", "element" => viewport}, state)

      assert state.follow == true
      assert state.selected_id == "l4"
      assert state.offset == 2

      {{:change, _payload}, state} =
        LogView.handle_event(:ignore, %{"key" => "f", "element" => viewport}, state)

      assert state.follow == false
      assert state.selected_id == "l4"
    end
  end

  describe "handle_modifiers/3" do
    test "uses high-contrast selected style" do
      state = LogView.init(sample_children(), %{}, %{})

      selected_mods =
        LogView.handle_modifiers(
          :child,
          [{:"log-id", state.selected_id}, level: "error", message: "database timeout"],
          state
        )

      assert Keyword.get(selected_mods, :selected) == true
      assert "bg-15 text-0 bold" in Keyword.get_values(selected_mods, :style)

      unselected_mods =
        LogView.handle_modifiers(
          :child,
          [{:"log-id", "l3"}, level: "error", message: "database timeout"],
          state
        )

      refute Keyword.has_key?(unselected_mods, :selected)
      assert "text-196" in Keyword.get_values(unselected_mods, :style)
    end
  end

  describe "helpers" do
    test "push/3 trims to max entries" do
      entries =
        []
        |> LogView.push({:info, "one"}, 2)
        |> LogView.push({:warning, "two"}, 2)
        |> LogView.push({:error, "three"}, 2)

      assert length(entries) == 2
      assert Enum.map(entries, & &1.message) == ["two", "three"]
    end

    test "push/3 preserves explicit ids" do
      [entry] = LogView.push([], %{id: 123, level: :info, message: "ok"}, 10)
      assert entry.id == 123
    end

    test "format_entry/2 renders level prefix" do
      line = LogView.format_entry(%{level: :warning, message: "slow query", source: :ecto})
      assert String.contains?(line, "[WARNING]")
      assert String.contains?(line, "slow query")
    end
  end
end
