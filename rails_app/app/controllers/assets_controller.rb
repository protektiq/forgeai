# frozen_string_literal: true

class AssetsController < ApplicationController
  before_action :set_asset, only: [:show, :download]

  def index
    @search_query = params[:q].to_s.strip
    index_service_url = Rails.application.config.index_service_url.presence

    if @search_query.present?
      if index_service_url.present?
        @assets = fetch_assets_via_search(@search_query, index_service_url)
        @search_unavailable = false
      else
        @assets = current_user.assets.order(created_at: :desc)
        @search_unavailable = true
      end
    else
      @assets = current_user.assets.order(created_at: :desc)
      @search_unavailable = false
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

  def fetch_assets_via_search(query, base_url)
    search_url = URI.join(base_url, "/search")
    search_url.query = URI.encode_www_form(q: query)

    req = Net::HTTP::Get.new(search_url)
    req["Accept"] = "application/json"

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
