# frozen_string_literal: true

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  # Required for Devise mailer links (e.g. password reset)
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }

  # Store uploaded/generated files on local disk
  config.active_storage.service = :local
end
