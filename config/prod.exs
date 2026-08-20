import Config

# The digest manifest is built by `mix assets.deploy` when the image is built.
# Only the two consoles have one; the API serves a favicon and nothing else.
for {app, endpoint} <- [{:sca_web, ScaWeb.Endpoint}, {:sca_admin, ScaAdmin.Endpoint}] do
  config app, endpoint, cache_static_manifest: "priv/static/cache_manifest.json"
end

# Configure Swoosh API Client
config :swoosh, :api_client, Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# In production logs are read by a collector, not a person.
config :logster, formatter: :json
