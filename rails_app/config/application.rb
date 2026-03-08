# frozen_string_literal: true

require_relative "boot"

# require "rails"
# require "active_model/railtie"
# require "active_job/railtie"
# require "action_controller/railtie"
# require "action_view/railtie"
# require "rails/test_unit/railtie"
require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module RailsApp
  class Application < Rails::Application
    config.load_defaults 7.0
    config.api_only = false
    config.root = File.expand_path("..", __dir__)

    config.active_job.queue_adapter = :sidekiq

    # External pipeline services (configurable via ENV for deployment)
    config.generator_url = ENV.fetch("GENERATOR_URL", "http://localhost:5000")
    config.generator_backend = ENV.fetch("GENERATOR_BACKEND", "pillow_mock")
    config.media_service_command = ENV.fetch("MEDIA_SERVICE_COMMAND", "")
    config.cpp_media_url = ENV.fetch("CPP_MEDIA_URL", "").strip.presence
    config.index_service_url = ENV.fetch("INDEX_SERVICE_URL", "").strip.presence
    config.dotnet_api_url = ENV.fetch("DOTNET_API_URL", "").strip.presence

    # Timeouts (seconds) and retry counts for outbound HTTP calls
    config.generator_open_timeout = ENV.fetch("GENERATOR_OPEN_TIMEOUT", "10").to_i
    config.generator_read_timeout = ENV.fetch("GENERATOR_READ_TIMEOUT", "60").to_i
    config.generator_retries = ENV.fetch("GENERATOR_RETRIES", "2").to_i
    config.media_open_timeout = ENV.fetch("MEDIA_OPEN_TIMEOUT", "10").to_i
    config.media_read_timeout = ENV.fetch("MEDIA_READ_TIMEOUT", "60").to_i
    config.media_retries = ENV.fetch("MEDIA_RETRIES", "2").to_i
    config.index_open_timeout = ENV.fetch("INDEX_OPEN_TIMEOUT", "10").to_i
    config.index_read_timeout = ENV.fetch("INDEX_READ_TIMEOUT", "10").to_i
    config.index_retries = ENV.fetch("INDEX_RETRIES", "2").to_i
    config.index_service_command = ENV.fetch("INDEX_SERVICE_COMMAND", "")

    # Internal API (used by dotnet_api): API user and optional key check
    config.api_user_id = ENV.fetch("API_USER_ID", "").strip.presence
    config.rails_internal_api_key = ENV.fetch("RAILS_INTERNAL_API_KEY", "").strip.presence
    config.host_for_blob_urls = ENV.fetch("HOST_FOR_BLOB_URLS", "").strip.presence

    config.middleware.use Rack::Attack
  end
end
