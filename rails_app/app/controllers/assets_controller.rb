# frozen_string_literal: true

class AssetsController < ApplicationController
  before_action :set_asset, only: [:show, :download]

  def index
    @search_query = params[:q].to_s.strip
    index_service_url = Rails.application.config.index_service_url.presence
    # All outbound requests from Rails must set X-Correlation-Id for tracing.
    correlation_id = request.request_id.presence || SecureRandom.uuid

    if @search_query.present?
      if index_service_url.present?
        unless index_service_ready?(index_service_url, correlation_id)
          @search_starting_up = true
          @assets = current_user.assets.order(created_at: :desc)
          @search_unavailable = false
        else
          @assets = fetch_assets_via_search(@search_query, index_service_url, correlation_id)
          @search_starting_up = false
          @search_unavailable = false
        end
      else
        @assets = current_user.assets.order(created_at: :desc)
        @search_unavailable = true
        @search_starting_up = false
      end
    else
      @assets = current_user.assets.order(created_at: :desc)
      @search_unavailable = false
      @search_starting_up = false
    end
  end

  def show
    # set_asset ensures ownership; 404 if not found or wrong user
  end

  def download
    unless @asset.file.attached?
      redirect_to asset_path(@asset), alert: "File not available yet."
      return
    end
    redirect_to rails_blob_path(@asset.file, disposition: "attachment")
  end

  private

  def index_service_ready?(base_url, correlation_id = nil)
    ready_url = URI.join(base_url, "/ready")
    req = Net::HTTP::Get.new(ready_url)
    req["Accept"] = "application/json"
    req["X-Correlation-Id"] = correlation_id if correlation_id.present?
    res = nil
    Net::HTTP.start(ready_url.host, ready_url.port, open_timeout: 2, read_timeout: 2) do |http|
      res = http.request(req)
    end
    res.is_a?(Net::HTTPSuccess)
  rescue StandardError
    false
  end

  def fetch_assets_via_search(query, base_url, correlation_id = nil)
    search_url = URI.join(base_url, "/search")
    search_url.query = URI.encode_www_form(q: query)

    req = Net::HTTP::Get.new(search_url)
    req["Accept"] = "application/json"
    req["X-Correlation-Id"] = correlation_id if correlation_id.present?

    res = nil
    Net::HTTP.start(search_url.host, search_url.port, open_timeout: 5, read_timeout: 5) do |http|
      res = http.request(req)
    end

    unless res.is_a?(Net::HTTPSuccess)
      return current_user.assets.none
    end

    data = JSON.parse(res.body) rescue {}
    asset_ids = Array(data["asset_ids"]).map(&:to_s).reject(&:blank?)
    return current_user.assets.none if asset_ids.empty?

    current_user.assets.where(id: asset_ids).order(created_at: :desc)
  end

  def set_asset
    @asset = current_user.assets.find_by(id: params[:id])
    unless @asset
      head :not_found
      return
    end
  end
end
