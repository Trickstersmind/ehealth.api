use Mix.Config

# Configuration for production environment.
# It should read environment variables to follow 12 factor apps convention.

# For production, we often load configuration from external
# sources, such as your system environment. For this reason,
# you won't find the :http configuration below, but set inside
# EHealth.Web.Endpoint.load_from_system_env/1 dynamically.
# Any dynamic configuration should be moved to such function.
#
# Don't forget to configure the url host to something meaningful,
# Phoenix uses this information when generating URLs.
#
# Finally, we also include the path to a cache manifest
# containing the digested version of static files. This
# manifest is generated by the mix phoenix.digest task
# which you typically run after static files are built.
config :ehealth, EHealth.Web.Endpoint,
  load_from_system_env: true,
  http: [port: {:system, "PORT", "80"}],
  url: [
    host: {:system, "HOST", "localhost"},
    port: {:system, "PORT", "80"}
  ],
  secret_key_base: {:system, "SECRET_KEY"},
  debug_errors: false,
  code_reloader: false

# Do not log passwords, card data and tokens
config :phoenix, :filter_parameters, ["password", "secret", "token", "password_confirmation", "card", "pan", "cvv"]

config :ehealth, EHealth.Scheduler,
  jobs: [
    medication_request_request_autotermination: [
      schedule: "* * * * *",
      task: {EHealth.MedicationRequestRequests, :autoterminate, []}
    ]
  ]

# ## SSL Support
#
# To get SSL working, you will need to add the `https` key
# to the previous section and set your `:url` port to 443:
#
#     config :sample2, Sample2.Web.Endpoint,
#       ...
#       url: [host: "example.com", port: 443],
#       https: [:inet6,
#               port: 443,
#               keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
#               certfile: System.get_env("SOME_APP_SSL_CERT_PATH")]
#
# Where those two env variables return an absolute path to
# the key and cert in disk or a relative path inside priv,
# for example "priv/ssl/server.key".
#
# We also recommend setting `force_ssl`, ensuring no data is
# ever sent via http, always redirecting to https:
#
#     config :sample2, Sample2.Web.Endpoint,
#       force_ssl: [hsts: true]
#
# Check `Plug.SSL` for all available options in `force_ssl`.

# ## Using releases
#
# If you are doing OTP releases, you need to instruct Phoenix
# to start the server for all endpoints:
#
#     config :phoenix, :serve_endpoints, true
#
# Alternatively, you can configure exactly which server to
# start per endpoint:
#
#     config :sample2, Sample2.Web.Endpoint, server: true
#
config :phoenix, :serve_endpoints, true

# Configure your database
config :ehealth, EHealth.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "${DB_NAME}",
  username: "${DB_USER}",
  password: "${DB_PASSWORD}",
  hostname: "${DB_HOST}",
  port: "${DB_PORT}",
  pool_size: "${DB_POOL_SIZE}",
  timeout: 15_000,
  pool_timeout: 15_000,
  loggers: [{Ecto.LoggerJSON, :log, [:info]}]

config :ehealth, EHealth.PRMRepo,
  adapter: Ecto.Adapters.Postgres,
  database: "${PRM_DB_NAME}",
  username: "${PRM_DB_USER}",
  password: "${PRM_DB_PASSWORD}",
  hostname: "${PRM_DB_HOST}",
  port: "${PRM_DB_PORT}",
  pool_size: "${PRM_DB_POOL_SIZE}",
  timeout: 15_000,
  pool_timeout: 15_000,
  types: EHealth.PRM.PostgresTypes,
  loggers: [{Ecto.LoggerJSON, :log, [:info]}]

config :ehealth, EHealth.FraudRepo,
  adapter: Ecto.Adapters.Postgres,
  database: "${FRAUD_DB_NAME}",
  username: "${FRAUD_DB_USER}",
  password: "${FRAUD_DB_PASSWORD}",
  hostname: "${FRAUD_DB_HOST}",
  port: "${FRAUD_DB_PORT}",
  pool_size: "${FRAUD_DB_POOL_SIZE}",
  timeout: 15_000,
  pool_timeout: 15_000,
  types: EHealth.Fraud.PostgresTypes,
  loggers: [{Ecto.LoggerJSON, :log, [:info]}]

config :ehealth, EHealth.EventManagerRepo,
  adapter: Ecto.Adapters.Postgres,
  database: "${EVENT_MANAGER_DB_NAME}",
  username: "${EVENT_MANAGER_DB_USER}",
  password: "${EVENT_MANAGER_DB_PASSWORD}",
  hostname: "${EVENT_MANAGER_DB_HOST}",
  port: "${EVENT_MANAGER_DB_PORT}",
  pool_size: "${EVENT_MANAGER_DB_POOL_SIZE}",
  timeout: 15_000,
  pool_timeout: 15_000,
  loggers: [{Ecto.LoggerJSON, :log, [:info]}]
