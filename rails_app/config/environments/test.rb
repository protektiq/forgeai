# frozen_string_literal: true

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }

  config.active_storage.service = :test
end
