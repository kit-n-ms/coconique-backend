require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module KmAuthStarterApi
  class Application < Rails::Application
    config.load_defaults 8.0

    config.api_only = true

    # Coconique is a Japan-facing service; parse/display app times in JST while keeping DB storage in UTC.
    config.time_zone = "Tokyo"
    config.active_record.default_timezone = :utc

    # API mode では Cookie middleware が省かれるため、
    # HttpOnly Cookie 認証用に明示的に追加する
    config.middleware.use ActionDispatch::Cookies

    config.autoload_paths << Rails.root.join("app/lib")
    config.eager_load_paths << Rails.root.join("app/lib")
  end
end