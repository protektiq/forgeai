# frozen_string_literal: true

module Api
  module V1
    # Base for internal API controllers. Authenticates via X-Internal-Api-Key
    # when RAILS_INTERNAL_API_KEY is set; all actions are scoped to the API user.
    # Error responses use the standard shape: error.code, error.message, error.correlation_id (see docs/contracts/error-response.md).
    class BaseController < ActionController::API
      INTERNAL_API_KEY_HEADER = "X-Internal-Api-Key"

      before_action :authenticate_internal_api!
      before_action :set_api_user!
      before_action :set_request_correlation_id

      protected

      def set_request_correlation_id
        Thread.current[:correlation_id] = request.request_id.presence || SecureRandom.uuid
      end

      # Renders a JSON error response with the standard shape. Use for all API error responses.
      def render_api_error(message, status:)
        code = status_to_error_code(status)
        correlation_id = request.request_id.presence || SecureRandom.uuid
        payload = {
          error: {
            code: code,
            message: message.to_s,
            correlation_id: correlation_id,
          },
        }
        render json: payload, status: status
      end

      def status_to_error_code(status)
        sym = status.is_a?(Symbol) ? status : status.to_s.to_sym
        case sym
        when :unauthorized then "unauthorized"
        when :not_found then "not_found"
        when :bad_request then "invalid_request"
        when :unprocessable_entity then "validation_error"
        when :service_unavailable then "service_unavailable"
        when 429 then "rate_limit_exceeded"
        when 500 then "internal_error"
        when 502 then "bad_gateway"
        else "invalid_request"
        end
      end

      def authenticate_internal_api!
        configured_key = Rails.application.config.rails_internal_api_key
        return if configured_key.blank?

        provided = request.headers[INTERNAL_API_KEY_HEADER].to_s.strip
        return if provided.present? && ActiveSupport::SecurityUtils.secure_compare(configured_key, provided)

        render_api_error("Missing or invalid API key", status: :unauthorized)
      end

      def set_api_user!
        user_id = Rails.application.config.api_user_id
        if user_id.blank?
          # Fallback for dev: use first user
          @api_user = User.first
        else
          @api_user = User.find_by(id: user_id)
        end

        unless @api_user
          render_api_error("API user not configured or not found", status: :service_unavailable)
          return
        end
      end

      def api_user
        @api_user
      end
    end
  end
end
