# frozen_string_literal: true

module Api
  module V1
    # Base for internal API controllers. Authenticates via X-Internal-Api-Key
    # when RAILS_INTERNAL_API_KEY is set; all actions are scoped to the API user.
    class BaseController < ActionController::API
      INTERNAL_API_KEY_HEADER = "X-Internal-Api-Key"

      before_action :authenticate_internal_api!
      before_action :set_api_user!

      protected

      def authenticate_internal_api!
        configured_key = Rails.application.config.rails_internal_api_key
        return if configured_key.blank?

        provided = request.headers[INTERNAL_API_KEY_HEADER].to_s.strip
        return if provided.present? && ActiveSupport::SecurityUtils.secure_compare(configured_key, provided)

        head :unauthorized
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
          render json: { error: "API user not configured or not found" }, status: :service_unavailable
          return
        end
      end

      def api_user
        @api_user
      end
    end
  end
end
