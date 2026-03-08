# frozen_string_literal: true

module Admin
  # GET /admin/failures — recent failed workflow runs and failed generation jobs (legacy, no workflow_run_id).
  class FailuresController < ApplicationController
    FAILED_RUNS_LIMIT = 20
    FAILED_JOBS_LEGACY_LIMIT = 10

    def index
      @failed_runs = current_user.workflow_runs
        .where(status: "failed")
        .order(created_at: :desc)
        .limit(FAILED_RUNS_LIMIT)
        .includes(:workflow)

      @failed_jobs_legacy = current_user.generation_jobs
        .where(status: "failed", workflow_run_id: nil)
        .order(created_at: :desc)
        .limit(FAILED_JOBS_LEGACY_LIMIT)
    end
  end
end
