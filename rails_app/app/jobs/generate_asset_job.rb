# frozen_string_literal: true

class GenerateAssetJob < ApplicationJob
  include GenerationPipeline

  queue_as :default

  MAX_ERROR_MESSAGE_LENGTH = 1000

  discard_on(ActiveRecord::RecordNotFound) {}

  def perform(generation_job_id)
    job = GenerationJob.find_by(id: generation_job_id, status: "queued")
    return unless job

    Thread.current[:correlation_id] = job.correlation_id
    begin
      if job.workflow_run_id?
        run = WorkflowRun.find_by(id: job.workflow_run_id)
        return unless run

        Workflows::RunWorkflow.call(run)
        run.reload
        job.reload
        sync_job_from_run(job, run)
        return
      end

      run_legacy_pipeline(job)
    rescue StandardError => e
      job = GenerationJob.find_by(id: generation_job_id) if job.nil?
      mark_job_failed(job, e.message)
      update_workflow_run_on_failure(job)
    ensure
      Thread.current[:correlation_id] = nil
    end
  end

  private

  def run_legacy_pipeline(job)
    job.update!(status: "running", started_at: Time.current, error_message: nil)
    Rails.logger.info("[GenerateAssetJob] job_id=#{job.id} started")

    image_body = call_python_generator(job)
    return if job.reload.status == "failed"

    asset = store_image(job, image_body)
    return if job.reload.status == "failed"

    call_media_service(job, asset)
    return if job.reload.status == "failed"

    call_index_service(job, asset)
    return if job.reload.status == "failed"

    job.update!(status: "completed", completed_at: Time.current, error_message: nil)
    update_workflow_run_on_success(job, asset)
  end

  def sync_job_from_run(job, run)
    if run.status == "completed"
      job.update!(status: "completed", completed_at: Time.current, error_message: nil)
    elsif run.status == "failed"
      error_message = run.workflow_run_steps.where(status: "failed").order(:id).last&.error_message
      job.update!(
        status: "failed",
        completed_at: Time.current,
        error_message: error_message.to_s.truncate(MAX_ERROR_MESSAGE_LENGTH).presence || "Workflow failed"
      )
    end
  end

  def mark_job_failed(job, message)
    return unless job

    msg = message.to_s.truncate(MAX_ERROR_MESSAGE_LENGTH)
    job.update!(status: "failed", completed_at: Time.current, error_message: msg)
  end

  def update_workflow_run_on_success(job, asset)
    return unless job.workflow_run_id?

    run = WorkflowRun.find_by(id: job.workflow_run_id)
    return unless run

    run.update!(
      status: "completed",
      asset_id: asset&.id,
      generation_job_id: job.id
    )
    run.workflow_run_steps.update_all(
      status: "completed",
      completed_at: Time.current
    )
  end

  def update_workflow_run_on_failure(job)
    return unless job&.workflow_run_id?

    run = WorkflowRun.find_by(id: job.workflow_run_id)
    return unless run

    run.update!(
      status: "failed",
      generation_job_id: job.id
    )
    run.workflow_run_steps.update_all(
      status: "failed",
      completed_at: Time.current,
      error_message: job.error_message
    )
  end
end
