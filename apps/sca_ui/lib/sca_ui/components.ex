defmodule ScaUi.Components do
  @moduledoc """
  The Enum8 design system, as function components, shared by both consoles.

  Tailwind utilities and Heroicons outline only — no component library, no
  page-specific CSS. Everything a screen needs is here: `button/1`, `input/1`,
  `status/1`, `surface/1`, `row/1`, `page_header/1`, `copy_value/1` and
  `modal/1`.

  Three rules from the playbook are enforced by the components themselves:
  controls are 40px tall with an 8px radius, a status pill never looks
  interactive, and a value you are meant to copy carries its own button.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @primary "inline-flex h-10 items-center justify-center gap-2 rounded-lg bg-brand px-4 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-strong focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/30"
  @secondary "inline-flex h-10 items-center justify-center gap-2 rounded-lg border border-line bg-white px-4 text-sm font-semibold text-slate-700 shadow-sm transition hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/20"
  @ghost "inline-flex h-10 items-center justify-center gap-2 rounded-lg px-3 text-sm font-semibold text-slate-500 transition hover:bg-slate-50 hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/20"
  @control "h-10 w-full rounded-lg border border-line bg-white px-3 text-sm text-ink outline-none transition placeholder:text-slate-400 hover:border-slate-300 focus:border-brand focus:ring-4 focus:ring-brand/10"

  @doc """
  A button or a link that looks like one.

  One primary action per section; everything else is secondary or ghost.
  """
  attr(:variant, :string, default: "primary", values: ~w(primary secondary ghost))
  attr(:type, :string, default: nil)
  attr(:navigate, :string, default: nil)
  attr(:href, :string, default: nil)
  attr(:class, :string, default: nil)
  attr(:rest, :global, include: ~w(disabled form name value method))
  slot(:inner_block, required: true)

  def button(%{navigate: navigate} = assigns) when is_binary(navigate) do
    ~H"""
    <.link navigate={@navigate} class={[style(@variant), @class]} {@rest}>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  def button(%{href: href} = assigns) when is_binary(href) do
    ~H"""
    <.link href={@href} class={[style(@variant), @class]} {@rest}>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  def button(assigns) do
    ~H"""
    <button type={@type || "button"} class={[style(@variant), @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp style("primary"), do: @primary
  defp style("secondary"), do: @secondary
  defp style("ghost"), do: @ghost

  @doc """
  A labelled form control.

  `type="select"` renders the dropdown pattern: a native select with
  `appearance-none` and exactly one chevron, never the browser's arrow on top
  of ours.
  """
  attr(:id, :any, default: nil)
  attr(:name, :any)
  attr(:label, :string, default: nil)
  attr(:value, :any)
  attr(:type, :string, default: "text")
  attr(:field, Phoenix.HTML.FormField)
  attr(:errors, :list, default: [])
  attr(:help, :string, default: nil)
  attr(:options, :list, doc: "for type=select")
  attr(:prompt, :string, default: nil)
  attr(:rest, :global, include: ~w(autocomplete autofocus disabled placeholder readonly required))

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error/1))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "select"} = assigns) do
    assigns = assign(assigns, :control_class, @control)

    ~H"""
    <label class="block">
      <span :if={@label} class="mb-1.5 block text-xs font-semibold text-slate-700">{@label}</span>
      <span class="relative block">
        <select
          id={@id}
          name={@name}
          class={[@control_class, "cursor-pointer appearance-none pr-10"]}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
        <.icon
          name="hero-chevron-down"
          class="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400"
        />
      </span>
      <.input_footer errors={@errors} help={@help} />
    </label>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    assigns = assign(assigns, :control_class, @control)

    ~H"""
    <label class="block">
      <span :if={@label} class="mb-1.5 block text-xs font-semibold text-slate-700">{@label}</span>
      <textarea
        id={@id}
        name={@name}
        rows="4"
        class={[@control_class, "h-auto py-2 font-mono"]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.input_footer errors={@errors} help={@help} />
    </label>
    """
  end

  def input(assigns) do
    assigns = assign(assigns, :control_class, @control)

    ~H"""
    <label class="block">
      <span :if={@label} class="mb-1.5 block text-xs font-semibold text-slate-700">{@label}</span>
      <input
        type={@type}
        id={@id}
        name={@name}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={@control_class}
        {@rest}
      />
      <.input_footer errors={@errors} help={@help} />
    </label>
    """
  end

  attr(:errors, :list, required: true)
  attr(:help, :string, default: nil)

  defp input_footer(assigns) do
    ~H"""
    <p :if={@help && @errors == []} class="mt-1.5 text-xs leading-5 text-muted">{@help}</p>
    <p :for={error <- @errors} class="mt-1.5 text-xs leading-5 text-rose-600">{error}</p>
    """
  end

  @doc """
  A read-only status pill.

  Never interactive, never a button: the decision belongs to the detail screen.
  """
  attr(:value, :any, required: true)
  attr(:class, :string, default: nil)

  def status(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide ring-1 ring-inset",
      tone(@value),
      @class
    ]}>
      {@value}
    </span>
    """
  end

  defp tone(value) when is_atom(value), do: value |> Atom.to_string() |> tone()

  defp tone(value) do
    case String.downcase(to_string(value)) do
      status when status in ~w(confirmed approved active delivered) ->
        "bg-emerald-50 text-emerald-700 ring-emerald-600/20"

      status when status in ~w(pending) ->
        "bg-blue-50 text-blue-700 ring-blue-600/20"

      status when status in ~w(declined revoked failed) ->
        "bg-rose-50 text-rose-700 ring-rose-600/20"

      _expired_or_inactive ->
        "bg-slate-100 text-slate-600 ring-slate-500/20"
    end
  end

  @doc "A bordered white card. Lists live inside one, divided by rows."
  attr(:class, :string, default: nil)
  slot(:inner_block, required: true)

  def surface(assigns) do
    ~H"""
    <section class={["overflow-hidden rounded-xl border border-line bg-white shadow-surface", @class]}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  A list of records, as a table.

  Columns line up under their labels — which is the whole point of a table and
  the reason rows are not a row of floated `div`s. Pass `stream` for a
  `phx-update="stream"` body; `rows` then carries `{dom_id, record}` pairs.

      <.table id="bindings" rows={@streams.bindings} stream>
        <:col :let={binding} label="Device">{binding.name}</:col>
        <:col :let={binding} label="Linked" align="right">{Format.relative(binding.activated_at)}</:col>
        <:action :let={binding}><.link navigate={...}>View</.link></:action>
      </.table>
  """
  attr(:id, :string, required: true)
  attr(:rows, :any, required: true)
  attr(:stream, :boolean, default: false)

  slot :col, required: true do
    attr(:label, :string)
    attr(:align, :string, values: ~w(left right))
    attr(:width, :string)
    attr(:hide_below, :string, values: ~w(sm md lg))
  end

  slot(:action)

  def table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full table-fixed border-collapse text-left">
        <thead>
          <tr class="border-b border-line bg-canvas/60">
            <th
              :for={col <- @col}
              scope="col"
              class={[
                "px-5 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-muted",
                col[:width],
                cell_align(col[:align]),
                hidden_below(col[:hide_below])
              ]}
            >
              {col[:label]}
            </th>
            <th :if={@action != []} scope="col" class="w-24 px-5 py-2.5">
              <span class="sr-only">Actions</span>
            </th>
          </tr>
        </thead>

        <tbody id={@id} phx-update={@stream && "stream"} class="divide-y divide-line">
          <tr :for={row <- @rows} id={row_dom_id(row)} class="hover:bg-canvas/60">
            <td
              :for={col <- @col}
              class={[
                "px-5 py-3 align-middle text-sm text-ink",
                col[:width],
                cell_align(col[:align]),
                hidden_below(col[:hide_below])
              ]}
            >
              {render_slot(col, row_record(row))}
            </td>
            <td :if={@action != []} class="px-5 py-3 text-right align-middle">
              {render_slot(@action, row_record(row))}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp row_dom_id({dom_id, _record}) when is_binary(dom_id), do: dom_id
  defp row_dom_id(_row), do: nil

  defp row_record({dom_id, record}) when is_binary(dom_id), do: record
  defp row_record(row), do: row

  defp cell_align("right"), do: "text-right"
  defp cell_align(_left), do: "text-left"

  defp hidden_below(nil), do: nil
  defp hidden_below(breakpoint), do: "hidden #{breakpoint}:table-cell"

  @doc """
  One `label — value` pair on a detail screen.

  The label column is fixed, so values start on the same line down the card
  instead of drifting to whatever edge the text ends at.
  """
  attr(:label, :string, required: true)
  attr(:class, :string, default: nil)
  slot(:inner_block, required: true)

  def field(assigns) do
    ~H"""
    <div class={["flex items-baseline gap-4 border-b border-line px-5 py-3 last:border-b-0", @class]}>
      <dt class="w-40 shrink-0 text-xs text-muted">{@label}</dt>
      <dd class="min-w-0 flex-1 text-sm text-ink">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  @doc "One row of a list: 68px tall, divided from the next by a line."
  attr(:id, :string, default: nil)
  attr(:class, :string, default: nil)
  slot(:inner_block, required: true)

  def row(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "flex min-h-[68px] items-center gap-3 border-b border-line px-5 py-3 last:border-b-0",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "The header of a page: eyebrow, title, one sentence, at most one action."
  attr(:eyebrow, :string, default: nil)
  attr(:title, :string, required: true)
  attr(:description, :string, default: nil)
  slot(:action)

  def page_header(assigns) do
    ~H"""
    <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div class="max-w-2xl">
        <p :if={@eyebrow} class="text-xs font-bold uppercase tracking-[0.14em] text-brand">
          {@eyebrow}
        </p>
        <h1 class="mt-2 text-2xl font-semibold tracking-tight text-ink">{@title}</h1>
        <p :if={@description} class="mt-2 text-sm leading-6 text-muted">{@description}</p>
      </div>
      <div :if={@action != []} class="shrink-0">{render_slot(@action)}</div>
    </div>
    """
  end

  @doc "The header inside a surface, above a list."
  attr(:title, :string, required: true)
  attr(:description, :string, default: nil)
  slot(:action)

  def list_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-3 border-b border-line px-5 py-4">
      <div>
        <h2 class="text-sm font-semibold text-ink">{@title}</h2>
        <p :if={@description} class="mt-0.5 text-xs text-muted">{@description}</p>
      </div>
      <div :if={@action != []}>{render_slot(@action)}</div>
    </div>
    """
  end

  @doc "What a list says when it has nothing to show — inside the surface, not instead of it."
  attr(:title, :string, required: true)
  attr(:description, :string, default: nil)

  def empty_state(assigns) do
    ~H"""
    <div class="px-5 py-12 text-center">
      <p class="text-sm font-semibold text-ink">{@title}</p>
      <p :if={@description} class="mt-1 text-xs text-muted">{@description}</p>
    </div>
    """
  end

  @doc "A modal. Consequential actions live here, never in a list row."
  attr(:id, :string, required: true)
  attr(:show, :boolean, default: false)
  attr(:on_cancel, JS, default: %JS{})
  attr(:title, :string, required: true)
  attr(:description, :string, default: nil)
  slot(:inner_block, required: true)
  slot(:footer)

  def modal(assigns) do
    ~H"""
    <div id={@id} class={["relative z-50", !@show && "hidden"]}>
      <div class="fixed inset-0 bg-ink/40" aria-hidden="true" />
      <div class="fixed inset-0 overflow-y-auto p-4 sm:p-6">
        <div class="mx-auto w-full max-w-lg rounded-2xl border border-line bg-white shadow-lg">
          <div class="flex items-start justify-between gap-4 border-b border-line px-6 py-5">
            <div>
              <h2 class="text-base font-semibold text-ink">{@title}</h2>
              <p :if={@description} class="mt-1 text-xs text-muted">{@description}</p>
            </div>
            <button
              type="button"
              phx-click={@on_cancel}
              class="rounded-lg p-1 text-slate-400 transition hover:bg-slate-50 hover:text-ink"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="h-5 w-5" />
            </button>
          </div>
          <div class="px-6 py-5">{render_slot(@inner_block)}</div>
          <div :if={@footer != []} class="flex justify-end gap-2 border-t border-line px-6 py-4">
            {render_slot(@footer)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc "Flash messages, pinned top-right."
  attr(:flash, :map, required: true)

  def flash_group(assigns) do
    ~H"""
    <div class="fixed top-4 right-4 z-50 flex w-80 flex-col gap-2">
      <.flash :for={{kind, message} <- @flash} kind={kind} message={message} />
    </div>
    """
  end

  attr(:kind, :any, required: true)
  attr(:message, :string, required: true)

  defp flash(assigns) do
    ~H"""
    <div
      role="alert"
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> JS.hide()}
      class={[
        "rounded-xl border px-4 py-3 text-sm shadow-surface",
        @kind in [:info, "info"] && "border-brand/20 bg-brand-soft text-brand-strong",
        @kind in [:error, "error"] && "border-rose-200 bg-rose-50 text-rose-700"
      ]}
    >
      {@message}
    </div>
    """
  end

  @doc """
  A value with a copy button beside it — a key, a one-time password, a token.

  The button sits next to what it copies rather than in the corner of the
  dialog: with two codes on one screen, a button labelled "Copy" says nothing
  about which one it takes. And since a clipboard write has nothing to show for
  itself, the value blinks when it lands.
  """
  attr(:id, :string, required: true)
  attr(:value, :string, required: true)
  attr(:title, :string, default: "Copy")
  attr(:class, :string, default: nil, doc: "styling for the value itself")

  def copy_value(assigns) do
    ~H"""
    <div class="flex w-full items-start justify-between gap-2">
      <span id={@id} class={["min-w-0 break-all rounded", @class]}>{@value}</span>
      <button
        type="button"
        phx-click={copy(@id)}
        title={@title}
        aria-label={@title}
        class="inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-md text-slate-400 transition hover:bg-slate-100 hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/20"
      >
        <.icon name="hero-clipboard-document" class="h-4 w-4" />
      </button>
    </div>
    """
  end

  # The clipboard write is the browser's; the blink is entirely client-side, so
  # copying a password never costs a round trip to the server.
  defp copy(id) do
    "sca:copy"
    |> JS.dispatch(to: "##{id}")
    |> JS.transition("animate-copied", to: "##{id}", time: 900)
  end

  @doc "A Heroicons outline glyph."
  attr(:name, :string, required: true)
  attr(:class, :string, default: "h-5 w-5")

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
