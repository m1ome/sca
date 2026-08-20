defmodule ScaUi.Shell do
  @moduledoc """
  The console chrome both apps wear: a 228px sidebar on desktop, a fixed icon
  bar on mobile, and a 64px header that always says where you are and who you
  are.

  What differs between the client portal and the admin console is the
  navigation and the name in the corner, so those are arguments.
  """

  use Phoenix.Component

  import ScaUi.Components

  @doc """
  The signed-in shell.

      <ScaUi.Shell.console
        navigation={[{"Overview", ~p"/", "hero-squares-2x2"}]}
        active="Overview"
        title="Northstar Payments"
        subtitle="TNT-1"
        identity={@current_user.email}
        sign_out_path={~p"/log-out"}
        flash={@flash}
      >
  """
  attr :flash, :map, required: true
  attr :navigation, :list, required: true, doc: "{label, path, heroicon} triples"
  attr :active, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :identity, :string, required: true
  attr :identity_path, :string, default: nil
  attr :docs_path, :string, default: nil, doc: "the API documentation, when this console has one"
  attr :sign_out_path, :string, required: true
  slot :inner_block, required: true

  def console(assigns) do
    ~H"""
    <div class="min-h-screen bg-canvas lg:grid lg:grid-cols-[228px_minmax(0,1fr)]">
      <aside class="hidden border-r border-line bg-white lg:sticky lg:top-0 lg:flex lg:h-screen lg:flex-col lg:px-4 lg:py-6">
        <div class="flex items-center gap-2 px-2">
          <.logo />
          <span class="min-w-0">
            <b class="block truncate text-sm tracking-tight text-ink">{@title}</b>
            <small
              :if={@subtitle}
              class="block text-[10px] font-bold uppercase tracking-[0.13em] text-muted"
            >
              {@subtitle}
            </small>
          </span>
        </div>

        <nav class="mt-8 flex flex-col gap-1">
          <.link
            :for={{label, path, icon} <- @navigation}
            navigate={path}
            class={[
              "flex h-10 items-center gap-3 rounded-lg px-3 text-sm font-medium transition",
              (@active == label && "bg-brand-soft text-brand") ||
                "text-slate-500 hover:bg-slate-50 hover:text-ink"
            ]}
          >
            <.icon name={icon} class="h-[18px] w-[18px]" />
            {label}
          </.link>
        </nav>
      </aside>

      <main class="min-w-0 pb-20 lg:pb-0">
        <header class="sticky top-0 z-30 border-b border-line bg-white">
          <div class="flex h-16 items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
            <span class="text-sm font-semibold text-ink">{@active}</span>

            <div class="flex items-center gap-3">
              <.link
                :if={@docs_path}
                href={@docs_path}
                target="_blank"
                title="API documentation"
                class="inline-flex h-9 items-center gap-2 rounded-lg px-3 text-xs font-semibold text-slate-600 transition hover:bg-slate-50 hover:text-ink"
              >
                <.icon name="hero-book-open" class="h-4 w-4" />
                <span class="hidden sm:inline">API docs</span>
              </.link>
              <.link
                :if={@identity_path}
                navigate={@identity_path}
                title="Your account"
                class="hidden items-center gap-2 rounded-lg px-2 py-1 text-xs text-muted transition hover:bg-slate-50 hover:text-ink sm:flex"
              >
                <.icon name="hero-user-circle" class="h-4 w-4" />
                {@identity}
              </.link>
              <span :if={!@identity_path} class="hidden text-xs text-muted sm:block">
                {@identity}
              </span>
              <.link
                href={@sign_out_path}
                method="delete"
                class="inline-flex h-9 items-center gap-2 rounded-lg border border-line px-3 text-xs font-semibold text-slate-600 transition hover:bg-slate-50"
              >
                <.icon name="hero-arrow-right-start-on-rectangle" class="h-4 w-4" /> Sign out
              </.link>
            </div>
          </div>
        </header>

        <div class="px-4 py-6 sm:px-6 sm:py-8 lg:px-8">
          {render_slot(@inner_block)}
        </div>
      </main>

      <nav class="fixed inset-x-0 bottom-0 z-40 flex border-t border-line bg-white lg:hidden">
        <.link
          :for={{label, path, icon} <- @navigation}
          navigate={path}
          class={[
            "flex flex-1 flex-col items-center gap-1 py-2.5 text-[10px] font-semibold transition",
            (@active == label && "text-brand") || "text-slate-500"
          ]}
        >
          <.icon name={icon} class="h-5 w-5" />
          {label}
        </.link>
      </nav>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc "The shell for pages nobody has signed into yet."
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def public(assigns) do
    ~H"""
    <div class="grid min-h-screen place-items-center bg-canvas px-4 py-10">
      <div class="w-full max-w-sm">
        {render_slot(@inner_block)}
      </div>
      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc "The Enum8 shield."
  attr :class, :string, default: "h-8 w-8"

  def logo(assigns) do
    ~H"""
    <span class={["inline-flex shrink-0 text-brand", @class]}>
      <svg viewBox="0 0 40 40" fill="none" aria-hidden="true">
        <path
          d="M20 3.5 33 8v10.2c0 8.2-5.3 14.2-13 18.3C12.3 32.4 7 26.4 7 18.2V8l13-4.5Z"
          stroke="currentColor"
          stroke-width="2.3"
        />
        <path
          d="M12.8 20c3.4-5.9 7.7-5.9 10.2-1.5 2.1 3.7 4.2 3.7 5.5.2M27.2 20c-3.4 5.9-7.7 5.9-10.2 1.5-2.1-3.7-4.2-3.7-5.5-.2"
          stroke="currentColor"
          stroke-width="2.3"
          stroke-linecap="round"
        />
      </svg>
    </span>
    """
  end
end
