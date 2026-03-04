# frozen_string_literal: true

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.public_file_server.enabled = true
  config.action_mailer.default_url_options = { host: ENV.fetch("HOST", "localhost"), protocol: "https" }
end
