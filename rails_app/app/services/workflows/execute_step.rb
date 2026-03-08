# frozen_string_literal: true

module Workflows
  # Executes a single workflow step: sets run_step to running, runs the step
  # (generate/thumbnail/process/index) using pipeline helpers, then persists
  # status (completed or failed) with output or error_message.
  class ExecuteStep
    include GenerationPipeline

    MAX_ERROR_MESSAGE_LENGTH = 1000

    def self.call(run, run_step, generation_job:, asset:)
      new(run, run_step, generation_job: generation_job, asset: asset).call
    end

    def initialize(run, run_step, generation_job:, asset:)
      @run = run
      @run_step = run_step
      @generation_job = generation_job
      @asset = asset
    end

    def call
      @run_step.update!(status: "running", started_at: Time.current)

      success = execute_step
      if success
        @run_step.update!(
          status: "completed",
          completed_at: Time.current,
          error_message: nil
        )
      else
        mark_run_step_failed
      end
      success
    end

    private

    def execute_step
      step_type = @run_step.workflow_step.step_type

      case step_type
      when "generate"
        execute_generate_step
      when "thumbnail"
        execute_thumbnail_step
      when "process"
        execute_process_step
      when "index"
        execute_index_step
      else
        @run_step.update!(
          status: "failed",
          completed_at: Time.current,
          error_message: "Unknown step type: #{step_type}"
        )
        false
      end
    end

    def execute_generate_step
      job = @run.generation_job
      unless job
        job = GenerationJob.create!(
          user_id: @run.user_id,
          workflow_run_id: @run.id,
          prompt: @run.prompt,
          correlation_id: @run.correlation_id,
          status: "running",
          started_at: Time.current
        )
        @run.update!(generation_job_id: job.id)
      end

      payload = call_python_generator(job, @run_step.workflow_step.config)
      return false if payload.nil? || job.reload.status == "failed"

      created_asset = store_image(job, payload)
      return false if created_asset.nil? || job.reload.status == "failed"

      @run.update!(asset_id: created_asset.id)
      output = {
        "asset_id" => created_asset.id,
        "generation_job_id" => job.id,
        "backend" => payload[:backend].to_s,
        "model" => payload[:model].to_s,
        "duration_ms" => payload[:duration_ms],
        "seed" => payload[:seed]
      }
      @run_step.update!(output: output)
      true
    end

    def execute_thumbnail_step
      return false unless @generation_job && @asset

      call_media_service(@generation_job, @asset, profile: GenerationPipeline::MEDIA_PROFILE_THUMBNAIL_SQUARE)
      return false if @generation_job.reload.status == "failed"

      true
    end

    def execute_process_step
      return false unless @generation_job && @asset

      call_media_service(@generation_job, @asset, profile: GenerationPipeline::MEDIA_PROFILE_WEB_OPTIMIZED)
      return false if @generation_job.reload.status == "failed"

      true
    end

    def execute_index_step
      return false unless @generation_job && @asset

      call_index_service(@generation_job, @asset)
      return false if @generation_job.reload.status == "failed"

      true
    end

    def mark_run_step_failed
      message = @generation_job&.error_message.presence || "Step failed"
      @run_step.update!(
        status: "failed",
        completed_at: Time.current,
        error_message: message.to_s.truncate(MAX_ERROR_MESSAGE_LENGTH)
      )
    end
  end
end
