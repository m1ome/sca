defmodule Sca.Repos.TenantRepo do
  @moduledoc """
  Persistence for tenants. No rules live here — see `Sca.Actions.Tenant`.
  """

  use Sca.Repo.Base, model: Sca.Models.Tenant
end
