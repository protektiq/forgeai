# frozen_string_literal: true

class OrchestrateWorkflowJob < ApplicationJob
  include GenerationPipeline

  queue_as :default

  MAX_ERROR_MESSAGE_LENGTH = 1000

  discard_on(ActiveRecord::RecordNotFound) {}

  def perform(workflow_run_id)
    run = WorkflowRun.find_by(id: workflow_run_id)
    return unless run
    return unless run.status == "queued"

    run.update!(status: "running")
    Rails.logger.info("[OrchestrateWorkflowJob] workflow_run_id=#{run.id} correlation_id=#{run.correlation_id}")

    generation_job = nil
    asset = nil

    run.workflow_run_steps
       .joins(:workflow_step)
       .order("workflow_steps.execution_order")
       .each do |run_step|
      run_step.update!(status: "running", started_at: Time.current)

      success = execute_step(run, run_step, generation_job: generation_job, asset: asset)
      unless success
        mark_run_step_failed(run_step, generation_job&.error_message)
        run.update!(status: "failed", generation_job_id: generation_job&.id)
        return
      end

      run.reload
      generation_job = run.generation_job if run.generation_job_id?
      asset = run.asset if run.asset_id?

      run_step.update!(status: "completed", completed_at: Time.current, error_message: nil)
    end

    run.update!(status: "completed", asset_id: asset&.id)
  rescue StandardError => e
    run = WorkflowRun.find_by(id: workflow_run_id)
    return unless run

    run.update!(status: "failed")
    msg = e.message.to_s.truncate(MAX_ERROR_MESSAGE_LENGTH)
    run.workflow_run_steps.where(status: %w[pending running]).update_all(
      status: "failed",
      completed_at: Time.current,
      error_message: msg
    )
  end

  private

  def execute_step(run, run_step, generation_job:, asset:)
    step_type = run_step.workflow_step.step_type

    case step_type
    when "generate"
      execute_generate_step(run, run_step)
    when "store"
      execute_store_step(run, run_step, generation_job)
    when "thumbnail"
      execute_thumbnail_step(run_step, generation_job, asset)
    when "index"
      execute_index_step(run_step, generation_job, asset)
    else
      run_step.update!(status: "failed", error_message: "Unknown step type: #{step_type}", completed_at: Time.current)
      return false
    end
  end

  def execute_generate_step(run, run_step)
    job = run.generation_job
    unless job
      job = GenerationJob.create!(
        user_id: run.user_id,
        workflow_run_id: run.id,
        prompt: run.prompt,
        correlation_id: run.correlation_id,
        status: "running",
        started_at: Time.current
      )
      run.update!(generation_job_id: job.id)
    end

    payload = call_python_generator(job)
    return false if payload.nil? || job.reload.status == "failed"

    run_step.update!(output: payload.stringify_keys)
    true
  end

  def execute_store_step(run, run_step, generation_job)
    return false unless generation_job

    generate_run_step = run.workflow_run_steps
                          .joins(:workflow_step)
                          .find_by(workflow_steps: { step_type: "generate" })
    image_payload = generate_run_step&.output
    return false if image_payload.blank?

    payload = image_payload.is_a?(Hash) ? image_payload.symbolize_keys : image_payload
    created_asset = store_image(generation_job, payload)
    return false if created_asset.nil? || generation_job.reload.status == "failed"

    run.update!(asset_id: created_asset.id)
    true
  end

  def execute_thumbnail_step(run_step, generation_job, asset)
    return false unless generation_job && asset

    call_media_service(generation_job, asset)
    return false if generation_job.reload.status == "failed"

    true
  end

  def execute_index_step(run_step, generation_job, asset)
    return false unless generation_job && asset

    call_index_service(generation_job, asset)
    return false if generation_job.reload.status == "failed"

    true
  end

  def mark_run_step_failed(run_step, message)
    run_step.update!(
      status: "failed",
      completed_at: Time.current,
      error_message: message.to_s.truncate(MAX_ERROR_MESSAGE_LENGTH)
    )
  end
end
