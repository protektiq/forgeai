# frozen_string_literal: true

class ApplicationController < ActionController::Base
  before_action :authenticate_user!, unless: :devise_controller?
  before_action :set_request_correlation_id

  protected

  def set_request_correlation_id
    Thread.current[:correlation_id] = request.request_id.presence || SecureRandom.uuid
  end

  def after_sign_in_path_for(_resource)
    dashboard_path
  end

  def after_sign_up_path_for(_resource)
    dashboard_path
  end
end
