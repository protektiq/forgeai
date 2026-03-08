# frozen_string_literal: true

class OrchestrateWorkflowJob < ApplicationJob
  queue_as :default

  MAX_ERROR_MESSAGE_LENGTH = 1000

  discard_on(ActiveRecord::RecordNotFound) {}

  def perform(workflow_run_id)
    run = WorkflowRun.find_by(id: workflow_run_id)
    return unless run
    return unless run.status == "queued"

    Thread.current[:correlation_id] = run.correlation_id
    begin
      Rails.logger.info("[OrchestrateWorkflowJob] workflow_run_id=#{run.id} started")
      Workflows::RunWorkflow.call(run)
    rescue StandardError => e
      run = WorkflowRun.find_by(id: workflow_run_id)
      return unless run

      run.update!(status: "failed")
      msg = e.message.to_s.truncate(MAX_ERROR_MESSAGE_LENGTH)
      run.workflow_run_steps.where(status: %w[queued running]).update_all(
        status: "failed",
        completed_at: Time.current,
        error_message: msg
      )
    ensure
      Thread.current[:correlation_id] = nil
    end
  end
end
