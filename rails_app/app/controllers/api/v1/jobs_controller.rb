# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/jobs/:id — returns job status for the API user (for polling after create).
    class JobsController < BaseController
      def show
        job = api_user.generation_jobs.find_by(id: params[:id])
        unless job
          render_api_error("Job not found", status: :not_found)
          return
        end

        payload = {
          job_id: job.id,
          status: job.status,
          created_at: job.created_at,
          started_at: job.started_at,
          completed_at: job.completed_at
        }
        payload[:error_message] = job.error_message if job.error_message.present?
        payload[:asset_id] = job.asset.id if job.status == "completed" && job.asset.present?

        render json: payload
      end
    end
  end
end
