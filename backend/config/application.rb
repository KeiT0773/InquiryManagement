require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # 「今日」の日付（受付日・期限超過）は日本時間で決める。DB には UTC で保存する（データ設計書 5.4）
    config.time_zone = "Tokyo"

    # コントローラーの外で起きた失敗も Problem Details で返す（API 設計書 2.1）。
    # 起動の時点では lib/ のクラスをまだ読み込めないため、要求が来たときに参照する
    config.exceptions_app = ->(env) { ProblemDetailsExceptionsApp.call(env) }

    # 入力チェックのメッセージは日本語で返す（API 設計書 2.1）
    config.i18n.default_locale = :ja
    config.i18n.available_locales = [ :ja ]

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
  end
end
