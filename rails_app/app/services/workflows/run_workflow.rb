# frozen_string_literal: true

module Workflows
  # Orchestrates a workflow run: loads steps in order, skips completed steps,
  # executes each step via ExecuteStep, persists run status, stops on first failure.
  # Ensures correlation_id flows via run and generation_job.
  class RunWorkflow
    def self.call(run)
      new(run).call
    end

    def initialize(run)
      @run = run.is_a?(WorkflowRun) ? run : WorkflowRun.find_by(id: run)
    end

    def call
      return unless @run
      return unless @run.status == "queued"

      @run.update!(status: "running")
      Rails.logger.info("[RunWorkflow] workflow_run_id=#{@run.id} started")

      generation_job = nil
      asset = nil

      ordered_run_steps.each do |run_step|
        if run_step.status == "completed"
          @run.reload
          generation_job = @run.generation_job if @run.generation_job_id?
          asset = @run.asset if @run.asset_id?
          next
        end

        success = ExecuteStep.call(@run, run_step, generation_job: generation_job, asset: asset)
        unless success
          @run.update!(status: "failed", generation_job_id: generation_job&.id)
          return
        end

        @run.reload
        generation_job = @run.generation_job if @run.generation_job_id?
        asset = @run.asset if @run.asset_id?
      end

      @run.update!(status: "completed", asset_id: asset&.id)
    end

    private

    def ordered_run_steps
      @run.workflow_run_steps
          .joins(:workflow_step)
          .order("workflow_steps.execution_order")
    end
  end
end
