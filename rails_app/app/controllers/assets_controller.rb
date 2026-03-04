# frozen_string_literal: true

class AssetsController < ApplicationController
  before_action :set_asset, only: [:show, :download]

  def index
    @assets = current_user.assets.order(created_at: :desc)
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

  def set_asset
    @asset = current_user.assets.find_by(id: params[:id])
    unless @asset
      head :not_found
      return
    end
  end
end
