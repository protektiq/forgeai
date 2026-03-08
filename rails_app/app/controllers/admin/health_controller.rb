# frozen_string_literal: true

module Admin
  # GET /admin/health — probe Python, C++, Rust, .NET health endpoints and show status + last checked.
  class HealthController < ApplicationController
    HEALTH_PATH = "/health"
    TIMEOUT_SEC = 3

    def index
      @checked_at = Time.current
      @results = {
        python: probe_service("Python", Rails.application.config.generator_url),
        cpp: probe_service("C++", Rails.application.config.cpp_media_url),
        rust: probe_service("Rust", Rails.application.config.index_service_url),
        dotnet: probe_service(".NET", Rails.application.config.dotnet_api_url),
      }
    end

    private

    def probe_service(label, base_url)
      return { status: :not_configured, message: "Not configured", response_time_ms: nil } if base_url.blank?

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      url = URI.join(base_url.to_s.end_with?("/") ? base_url : "#{base_url}/", HEALTH_PATH)
      res = nil
      Net::HTTP.start(url.host, url.port, open_timeout: TIMEOUT_SEC, read_timeout: TIMEOUT_SEC) do |http|
        req = Net::HTTP::Get.new(url)
        req["Accept"] = "application/json"
        res = http.request(req)
      end
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      if res.is_a?(Net::HTTPSuccess)
        { status: :ok, message: "OK", response_time_ms: elapsed_ms }
      else
        { status: :error, message: "#{res.code} #{res.message}", response_time_ms: elapsed_ms }
      end
    rescue StandardError => e
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      { status: :unreachable, message: e.message.to_s.truncate(120), response_time_ms: elapsed_ms }
    end
  end
end
