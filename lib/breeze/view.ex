defmodule Breeze.View do
  @moduledoc """
  A Breeze View is a process that handles events, updates its states and renders
  to the terminal. Breeze Views are inspired by Phoenix LiveView, but not 100%
  compatible.

  > #### Warning {: .warning}
  >
  > This API is unstable and very likely to change.

  ## Usage

  The module can be used by including `use Breeze.View`:

  ```
  defmodule Demo do
    use Breeze.View
  end
  ```

  ## Initial state

  The initial state can be set in the mount callback:

  ```
  def mount(_opts, term), do: {:ok, assign(term, counter: 0)}
  ```

  ## Rendering

  Rendering is performed using Breeze's `~H` template sigil.


  ```
  def render(assigns) do
    ~H"<box>Counter: <%= @counter %></box>"
  end
  ```

  There are a handful of supported attributes:


  * `id` - the id of the element. This is required for focusables and implicits
  * `focusable` - if the element should be added to the focus tree. These are added in
  the order they appear, and can be toggled using tab/shift-tab. The `focus` style
     alias BackBreeze.Style
  state can be used to style these. E.g. style="border focus:border-3"
  * `style` - the style for the box. This is covered in the [Style](`m:Breeze.View#module-style`) section.
  * `implicit` - this is a module that will be used for implicit state. This is covered
   in the [Implicits](`m:Breeze.View#module-implicits`) section.

  ## Handling events

  Any events that come from the terminal or an implicit are handled in the `handle_event/3` callback:

  ```
  def handle_event(_, %{"key" => "ArrowUp"}, term) do
    {:noreply, assign(term, counter: term.assigns.counter + 1)}
  end

  def handle_event(_, %{"key" => "ArrowDown"}, term) do
    {:noreply, assign(term, counter: term.assigns.counter - 1)}
  end

  def handle_event(_, %{"key" => "q"}, term) do
    {:stop, term}
  end

  def handle_event(_, _, term) do
    {:noreply, term}
  end
  ```

  For convenience, keys are converted to a more friendly representation for example,
  instead of sending "\eA" which is provided by the terminal, we convert it to "ArrowUp".

  Any other messages sent to the process will be handled using `handle_info/2`:

  ```
  def handle_info(:some_message, term), do: {:noreply, term}
  ```

  ## Style

  The `style` attribute can be used to style the box. This uses `BackBreeze.Box.new/1` under
  the hood.

  A box can be styled similar to CSS using the style attribute:

  ```
  <box style="bold text-3 border width-15">Hello World</box>
  ```

  The following styles are supported:

   * `border` - add a line border to the box
   * `bold` - make the text bold
   * `italic` - make the text italic
   * `inverse` - reverse the foreground-background
   * `reverse` - reverse the foreground-background
   * `inline` - display the elements inline (join horizontally)
   * `width-x` - set the width of the element
   * `height-x` - set the height of the element
   * `absolute` - position the elements absolute relative to the parent
   * `border-x` - set the border color where x is a number
   * `bg-x` - set the background color where x is a number
   * `text-x` - set the foreground color where x is a number

  ## Implicits

  Implicits provide a way of adding event handler/state that exists outside of the view
  these should be abstracted out into their own components.

  For example, consider a list component:

  ```
  def render(assigns) do
  ~H\"\"\"
  <.list id={id} br-change="my_custom_event">
  <:item value="hello">Hello</:item>
  <:item value="world">World</:item>
  <:item value="foo">Foo</:item>
  </.list>
  \"\"\"

  def handle_event("my_custom_event", %{value: value}, term), do: ...
  ```

  Ideally, we don't want to have to keep track of the selected value, handle key events,
  etc within our view. In our view, we might only care about the selected value. In this case, we can define the list component to use an implicit state module.

  ```
  attr :id, :string, required: true
  attr :rest, :global

  slot :item do
    attr(:value, :string, required: true)
  end

  def list(assigns) do
    ~H\"\"\"
    <box focusable style="border focus:border-3" implicit={MyAppList} id={@id} {@rest}>
      <box
        :for={item <- @item}
        value={item.value}
        style="selected:bg-24 selected:text-0 focus:selected:text-7 focus:selected:bg-4"
      ><%= render_slot(item, %{}) %></box>
    </box>
    \"\"\"
  end
    ```

  The implicit module is first called with an `init/2` callback, which is called with all
  the attributes of all the child elements, and the previous state. This ensures that
  values persist between renders.

  ```
  defmodule MyAppList do

    def init(children, last_state) do
      %{values: Enum.map(children, &(&1.value)), selected: last_state[:selected]}
    end
  end
  ```

  There is also a `handle_event/3` callback. This is similar to the callback for a view, but
  returns different values. Here we handle key events and return a `:change` event along
  with the new state. The `:change` will be used by `br-change` to pass through to the handle_event
  callback of the Breeze.View.

  ```
  def handle_event(_, %{"key" => "ArrowDown"}, %{values: values} = state) do
    index = Enum.find_index(values, &(&1 == state.selected))
    value = if index, do: Enum.at(values, index + 1) || hd(values), else: hd(values)
    {{:change, %{value: value}}, %{state | selected: value}}
  end

  def handle_event(_, %{"key" => "ArrowUp"}, %{values: values} = state) do
    index = Enum.find_index(values, &(&1 == state.selected))
    first = hd(Enum.reverse(values))
    value = if index, do: Enum.at(values, index - 1) || first, else: first
    {{:change, %{value: value}}, %{state | selected: value}}
  end

  def handle_event(_, _, state), do: {:noreply, state}
  ```

  There is one final handler which is called when a child is being rendered.
  `handle_modifiers/2` can be used to tell the renderer things about the state.
  In this case, we want to add the `:selected` flag so that the list element is
  styled differently.

  ```
  def handle_modifiers(attributes, state) do
    if state.selected == Keyword.get(attributes, :value) do
      [selected: true]
    else
      []
    end
  end
  ```

  """

  defmacro __using__(_opts) do
    quote do
      import Breeze.View
      Module.register_attribute(__MODULE__, :breeze_components, accumulate: true)
      @before_compile Breeze.View
    end
  end

  defmacro sigil_H({:<<>>, _meta, [source]}, _modifiers) when is_binary(source) do
    unless Macro.Env.has_var?(__CALLER__, {:assigns, nil}) do
      raise "~H requires a variable named \"assigns\" to exist and be set to a map"
    end

    template = Breeze.Template.compile!(source, __CALLER__)

    template
    |> Breeze.Template.component_names()
    |> Enum.each(&Module.put_attribute(__CALLER__.module, :breeze_components, &1))

    quote do
      _ = var!(assigns)
      unquote(Macro.escape(template))
    end
  end

  defmacro __before_compile__(env) do
    components =
      env.module
      |> Module.get_attribute(:breeze_components)
      |> Enum.uniq()

    component_definitions =
      Enum.map(components, fn component ->
        quote do
          def __breeze_component__(unquote(component), assigns), do: unquote(component)(assigns)
        end
      end)

    quote do
      unquote_splicing(component_definitions)

      def __breeze_component__(name, _assigns) do
        raise UndefinedFunctionError, module: __MODULE__, function: name, arity: 1
      end
    end
  end

  defmacro attr(_name, _type) do
    quote(do: :ok)
  end

  defmacro attr(_name, _type, _opts) do
    quote(do: :ok)
  end

  defmacro slot(_name) do
    quote(do: :ok)
  end

  defmacro slot(_name, _opts) do
    quote(do: :ok)
  end

  def render_slot(slot), do: render_slot(slot, %{})
  def render_slot(nil, _), do: ""

  def render_slot(slots, assigns) when is_list(slots) do
    Enum.map_join(slots, "", &render_slot(&1, assigns))
  end

  def render_slot(%{__breeze_slot__: fun}, assigns) when is_function(fun, 1) do
    fun.(Map.new(assigns || %{}))
  end

  def render_slot(_slot, _) do
    ""
  end

  def assign(term, values) do
    %{term | assigns: Map.merge(term.assigns, Map.new(values))}
  end
end
