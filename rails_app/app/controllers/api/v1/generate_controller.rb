# frozen_string_literal: true

module Api
  module V1
    # POST /api/v1/generate — creates a GenerationJob for the API user and enqueues GenerateAssetJob.
    class GenerateController < BaseController
      def create
        prompt = params[:prompt].to_s.strip
        if prompt.blank?
          render_api_error("prompt is required", status: :unprocessable_entity)
          return
        end

        if prompt.length > 10_000
          render_api_error("prompt is too long (maximum 10000 characters)", status: :unprocessable_entity)
          return
        end

        job = api_user.generation_jobs.build(
          prompt: prompt,
          status: "queued",
          correlation_id: request.request_id.presence || SecureRandom.uuid
        )
        unless job.save
          render_api_error(job.errors.full_messages.join(", "), status: :unprocessable_entity)
          return
        end

        GenerateAssetJob.perform_later(job.id)
        render json: { job_id: job.id, status: "queued" }, status: :created
      end
    end
  end
end
