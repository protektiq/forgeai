# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module RailsApp
  class Application < Rails::Application
    config.load_defaults 7.0
    config.api_only = false
    config.root = File.expand_path("..", __dir__)

    config.active_job.queue_adapter = :sidekiq

    # External pipeline services (configurable via ENV for deployment)
    config.generator_url = ENV.fetch("GENERATOR_URL", "http://localhost:5000")
    config.media_service_command = ENV.fetch("MEDIA_SERVICE_COMMAND", "")
    config.cpp_media_url = ENV.fetch("CPP_MEDIA_URL", "").strip.presence
    config.index_service_url = ENV.fetch("INDEX_SERVICE_URL", "").strip.presence
    config.index_service_command = ENV.fetch("INDEX_SERVICE_COMMAND", "")

    # Internal API (used by dotnet_api): API user and optional key check
    config.api_user_id = ENV.fetch("API_USER_ID", "").strip.presence
    config.rails_internal_api_key = ENV.fetch("RAILS_INTERNAL_API_KEY", "").strip.presence
    config.host_for_blob_urls = ENV.fetch("HOST_FOR_BLOB_URLS", "").strip.presence
  end
end
