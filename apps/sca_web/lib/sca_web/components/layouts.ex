defmodule ScaWeb.Layouts do
  @moduledoc """
  The merchant console's chrome: the shared shell from `ScaUi`, wearing this
  app's navigation.
  """

  use ScaWeb, :html

  embed_templates "layouts/*"

  @navigation [
    {"Overview", "/", "hero-squares-2x2"},
    {"Bindings", "/bindings", "hero-device-phone-mobile"},
    {"Approvals", "/approvals", "hero-check-circle"},
    {"Webhooks", "/webhooks", "hero-arrow-up-right"},
    {"Team", "/team", "hero-users"},
    {"Settings", "/settings", "hero-cog-6-tooth"}
  ]

  @doc "The signed-in application shell."
  attr :flash, :map, required: true
  attr :current_user, :map, required: true
  attr :current_tenant, :map, required: true
  attr :active, :string, default: "Overview"
  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :navigation, @navigation)

    ~H"""
    <ScaUi.Shell.console
      flash={@flash}
      navigation={@navigation}
      active={@active}
      title={@current_tenant.name}
      subtitle={@current_tenant.public_id}
      identity={@current_user.email}
      identity_path={~p"/account"}
      docs_path={~p"/docs"}
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
