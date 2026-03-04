# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    @recent_jobs = current_user.generation_jobs.order(created_at: :desc).limit(20)
  end

  def create
    @job = current_user.generation_jobs.build(job_params)
    @job.status = "queued"
    @job.correlation_id = request.request_id.presence || SecureRandom.uuid

    if @job.save
      GenerateAssetJob.perform_later(@job.id)
      redirect_to dashboard_path, notice: "Generation started. Refresh to see status."
    else
      @recent_jobs = current_user.generation_jobs.order(created_at: :desc).limit(20)
      render :index, status: :unprocessable_entity
    end
  end

  private

  def job_params
    params.require(:generation_job).permit(:prompt)
  end
end
