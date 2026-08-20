defmodule ScaAdmin.Layouts do
  @moduledoc """
  The admin console's chrome: the shared shell from `ScaUi`, wearing the
  internal navigation.
  """

  use ScaAdmin, :html

  embed_templates "layouts/*"

  @navigation [
    {"Overview", "/", "hero-squares-2x2"},
    {"Tenants", "/tenants", "hero-building-office-2"},
    {"Bindings", "/bindings", "hero-device-phone-mobile"},
    {"Approvals", "/approvals", "hero-check-circle"},
    {"Team", "/team", "hero-users"},
    {"Settings", "/settings", "hero-cog-6-tooth"}
  ]

  @doc "The signed-in console shell."
  attr :flash, :map, required: true
  attr :current_admin, :map, required: true
  attr :active, :string, default: "Overview"
  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :navigation, @navigation)

    ~H"""
    <ScaUi.Shell.console
      flash={@flash}
      navigation={@navigation}
      active={@active}
      title="Enum8"
      subtitle="Admin console"
      identity={@current_admin.email}
      identity_path={~p"/settings"}
      sign_out_path={~p"/log-out"}
    >
      {render_slot(@inner_block)}
    </ScaUi.Shell.console>
    """
  end

  @doc "The shell for pages nobody has signed into yet."
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def public(assigns) do
    ~H"""
    <ScaUi.Shell.public flash={@flash}>{render_slot(@inner_block)}</ScaUi.Shell.public>
    """
  end

  defdelegate logo(assigns), to: ScaUi.Shell
end
