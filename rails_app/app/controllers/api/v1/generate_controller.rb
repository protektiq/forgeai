# frozen_string_literal: true

module Api
  module V1
    # POST /api/v1/generate — creates a generation (workflow path or legacy wrap).
    # With workflow_id or workflow_slug: creates WorkflowRun + steps, enqueues OrchestrateWorkflowJob.
    # Without: creates default WorkflowRun + steps + GenerationJob, enqueues GenerateAssetJob (backward compatible).
    class GenerateController < BaseController
      DEFAULT_WORKFLOW_SLUG = "generate_process_index"

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

        workflow = resolve_workflow
        if params[:workflow_id].present? || params[:workflow_slug].present?
          unless workflow
            render_api_error("Workflow not found", status: :not_found)
            return
          end
          create_workflow_run_and_enqueue(workflow, prompt)
          return
        end

        create_wrapped_run_and_enqueue(prompt)
      end

      private

      def resolve_workflow
        if params[:workflow_id].present?
          Workflow.find_by(id: params[:workflow_id])
        elsif params[:workflow_slug].to_s.strip.present?
          Workflow.find_by(slug: params[:workflow_slug].to_s.strip)
        else
          nil
        end
      end

      def create_workflow_run_and_enqueue(workflow, prompt)
        correlation_id = request.request_id.presence || SecureRandom.uuid
        run = api_user.workflow_runs.create!(
          workflow: workflow,
          prompt: prompt,
          status: "queued",
          correlation_id: correlation_id
        )
        workflow.workflow_steps.order(:execution_order).each do |step|
          run.workflow_run_steps.create!(workflow_step: step, status: "pending")
        end
        OrchestrateWorkflowJob.perform_later(run.id)
        render json: { workflow_run_id: run.id, status: "queued" }, status: :created
      end

      def create_wrapped_run_and_enqueue(prompt)
        workflow = Workflow.find_by(slug: DEFAULT_WORKFLOW_SLUG)
        unless workflow
          render_api_error("Default workflow not found; run db:seed", status: :service_unavailable)
          return
        end

        correlation_id = request.request_id.presence || SecureRandom.uuid
        run = api_user.workflow_runs.create!(
          workflow: workflow,
          prompt: prompt,
          status: "queued",
          correlation_id: correlation_id
        )
        workflow.workflow_steps.order(:execution_order).each do |step|
          run.workflow_run_steps.create!(workflow_step: step, status: "pending")
        end

        job = api_user.generation_jobs.build(
          prompt: prompt,
          status: "queued",
          correlation_id: correlation_id,
          workflow_run_id: run.id
        )
        unless job.save
          render_api_error(job.errors.full_messages.join(", "), status: :unprocessable_entity)
          return
        end

        run.update!(generation_job_id: job.id)
        GenerateAssetJob.perform_later(job.id)
        render json: { job_id: job.id, status: "queued" }, status: :created
      end
    end
  end
end
