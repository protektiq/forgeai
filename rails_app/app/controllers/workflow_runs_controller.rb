# frozen_string_literal: true

class WorkflowRunsController < ApplicationController
  def show
    @workflow_run = current_user.workflow_runs.find(params[:id])
    @run_steps = @workflow_run.workflow_run_steps
      .joins(:workflow_step)
      .order("workflow_steps.execution_order")
      .includes(:workflow_step)
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
