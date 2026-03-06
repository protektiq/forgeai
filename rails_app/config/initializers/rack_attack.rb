# frozen_string_literal: true

# Rate limit prompt creation (API and dashboard) to avoid overload. Allow 30 req/min per IP
# so a 10-prompt batch fits; tune via RACK_ATTACK_THROTTLE_LIMIT if needed.
class Rack::Attack
  throttle("prompt_create_per_ip", limit: (ENV["RACK_ATTACK_THROTTLE_LIMIT"] || "30").to_i, period: 1.minute) do |req|
    req.ip if req.post? && (req.path == "/api/v1/generate" || req.path == "/dashboard")
  end

  # API clients expect JSON; dashboard gets HTML so users see a message.
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    retry_after = (match_data && match_data[:period]) ? match_data[:period].to_s : "60"
    if request.path.start_with?("/api/")
      correlation_id = request.env["action_dispatch.request_id"].presence ||
        request.env["REQUEST_ID"].presence ||
        SecureRandom.uuid
      body = {
        error: {
          code: "rate_limit_exceeded",
          message: "Rate limit exceeded",
          correlation_id: correlation_id,
        },
      }.to_json
      [
        429,
        { "Content-Type" => "application/json", "Retry-After" => retry_after },
        [body],
      ]
    else
      [
        429,
        { "Content-Type" => "text/html; charset=utf-8", "Retry-After" => retry_after },
        ["<html><body><h1>Rate limit exceeded</h1><p>Too many requests. Please try again later.</p><p><a href=\"/dashboard\">Back to dashboard</a></p></body></html>"]
      ]
    end
  end
end
