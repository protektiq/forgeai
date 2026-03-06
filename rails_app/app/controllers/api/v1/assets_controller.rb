# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/assets and GET /api/v1/assets/:id — JSON list/detail for API user's assets.
    class AssetsController < BaseController
      def index
        search_query = params[:search].to_s.strip
        index_service_url = Rails.application.config.index_service_url.presence

        assets = if search_query.present? && index_service_url.present?
                   fetch_assets_via_search(search_query, index_service_url)
                 else
                   api_user.assets.order(created_at: :desc)
                 end

        render json: assets.map { |a| asset_json(a) }
      end

      def show
        asset = api_user.assets.find_by(id: params[:id])
        unless asset
          render_api_error("Asset not found", status: :not_found)
          return
        end

        render json: asset_json(asset)
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
          return api_user.assets.none
        end

        data = JSON.parse(res.body)
      rescue JSON::ParserError, TypeError
        return api_user.assets.none
      else
        asset_ids = Array(data["asset_ids"]).map(&:to_s).reject(&:blank?)
        return api_user.assets.none if asset_ids.empty?

        api_user.assets.where(id: asset_ids).order(created_at: :desc)
      end

      def asset_json(asset)
        prompt = asset.generation_job&.prompt
        download_url = nil
        if asset.file.attached?
          base = Rails.application.config.host_for_blob_urls.presence
          path = Rails.application.routes.url_helpers.rails_blob_path(asset.file, disposition: "attachment")
          download_url = base.present? ? "#{base.chomp('/')}#{path}" : path
        end

        {
          id: asset.id,
          created_at: asset.created_at.iso8601,
          prompt: prompt,
          metadata: asset.metadata || {},
          download_url: download_url,
        }
      end
    end
  end
end
