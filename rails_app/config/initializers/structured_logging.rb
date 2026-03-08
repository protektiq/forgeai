# frozen_string_literal: true

# Structured logging: one JSON object per line with timestamp, service, level, message,
# and when set correlation_id (set by jobs via Thread.current[:correlation_id] or by
# request middleware via Thread.current[:correlation_id]).
# Use Rails.logger.info("message") after setting Thread.current[:correlation_id] so the formatter includes it.
# The formatter must respond to push_tags/pop_tags/clear_tags! because Rails' TaggedLogging delegates to it.
module StructuredLogFormatter
  SERVICE_NAME = "rails_app"

  def self.call(severity, timestamp, _progname, msg)
    payload = {
      timestamp: timestamp.utc.iso8601(3),
      service: SERVICE_NAME,
      level: severity,
      message: msg.to_s
    }
    cid = Thread.current[:correlation_id].presence
    payload[:correlation_id] = cid if cid
    payload.to_json + "\n"
  end

  class Formatter
    def call(severity, timestamp, progname, msg)
      StructuredLogFormatter.call(severity, timestamp, progname, msg)
    rescue StandardError => e
      # Ensure we never return nil (Logger calls .size on the return value).
      { timestamp: Time.now.utc.iso8601(3), service: SERVICE_NAME, level: "ERROR", message: "Log formatter error: #{e.message}" }.to_json + "\n"
    end
    # Rack::Logger does logger.push_tags(*tags).size — push_tags must return something with .size (e.g. the tags array).
    def push_tags(*args)
      args
    end
    def pop_tags(*)
      # no-op; Rack::Logger calls pop_tags(count) after the request
    end
    def clear_tags!
      # no-op; TaggedLogging calls this on formatter during flush at request end
    end
    # Active Job's TaggedLogging calls formatter.current_tags when enqueuing
    def current_tags
      []
    end
    # Some code paths call formatter.tagged(*tags) { block }
    def tagged(*)
      yield self
    end
  end
end

Rails.application.config.after_initialize do
  if Rails.logger.respond_to?(:formatter=)
    Rails.logger.formatter = StructuredLogFormatter::Formatter.new
  end
end