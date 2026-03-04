# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    @recent_jobs = current_user.generation_jobs.order(created_at: :desc).limit(20)
  end

  def create
    @job = current_user.generation_jobs.build(job_params)
    @job.status = "pending"

    if @job.save
      redirect_to dashboard_path, notice: "Job created. Generation will run when the pipeline is connected."
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
