# frozen_string_literal: true

class DashboardController < ApplicationController
  DEFAULT_WORKFLOW_SLUG = "generate_process_index"

  def index
    @recent_jobs = current_user.generation_jobs.order(created_at: :desc).limit(20)
  end

  def create
    prompt = job_params[:prompt].to_s.strip
    if prompt.blank?
      @job = current_user.generation_jobs.build(job_params)
      @job.errors.add(:prompt, "can't be blank")
      @recent_jobs = current_user.generation_jobs.order(created_at: :desc).limit(20)
      render :index, status: :unprocessable_entity
      return
    end

    workflow = Workflow.find_by(slug: DEFAULT_WORKFLOW_SLUG)
    unless workflow
      @job = current_user.generation_jobs.build(job_params)
      @job.errors.add(:base, "Default workflow not found; run db:seed")
      @recent_jobs = current_user.generation_jobs.order(created_at: :desc).limit(20)
      render :index, status: :unprocessable_entity
      return
    end

    correlation_id = request.request_id.presence || SecureRandom.uuid
    run = current_user.workflow_runs.create!(
      workflow: workflow,
      prompt: prompt,
      status: "queued",
      correlation_id: correlation_id
    )
    workflow.workflow_steps.order(:execution_order).each do |step|
      run.workflow_run_steps.create!(workflow_step: step, status: "pending")
    end

    @job = current_user.generation_jobs.build(
      prompt: prompt,
      status: "queued",
      correlation_id: correlation_id,
      workflow_run_id: run.id
    )

    if @job.save
      run.update!(generation_job_id: @job.id)
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
