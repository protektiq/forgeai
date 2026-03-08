# frozen_string_literal: true

# Seed default workflow presets. Idempotent: use find_or_create_by! on slug,
# then replace steps so re-running seed yields the same presets.
# Step types: generate (includes store), thumbnail, process, index.
# Run with: bin/rails db:seed

def seed_workflow(slug:, name:, description: nil, steps:)
  w = Workflow.find_or_create_by!(slug: slug) do |workflow|
    workflow.name = name
    workflow.description = description
  end
  w.update!(name: name, description: description)

  # Replace steps only when no runs reference this workflow (avoid FK constraint)
  unless w.workflow_runs.exists?
    w.workflow_steps.destroy_all
    steps.each do |step_type, execution_order, config|
      config ||= {}
      w.workflow_steps.create!(step_type: step_type, execution_order: execution_order, config: config)
    end
  end
end

seed_workflow(
  slug: "generate_only",
  name: "Generate only",
  description: "Generate image and store; no thumbnail or index",
  steps: [
    ["generate", 0, {}]
  ]
)

seed_workflow(
  slug: "generate_thumbnail",
  name: "Generate + thumbnail",
  description: "Generate, store, and create thumbnail; no index",
  steps: [
    ["generate", 0, {}],
    ["thumbnail", 1, { "thumbnail_size" => 256, "resize_max" => 1200 }]
  ]
)

seed_workflow(
  slug: "generate_process_index",
  name: "Generate + process + index",
  description: "Full pipeline: generate, thumbnail, process, and index",
  steps: [
    ["generate", 0, {}],
    ["thumbnail", 1, { "thumbnail_size" => 256, "resize_max" => 1200 }],
    ["process", 2, {}],
    ["index", 3, {}]
  ]
)

Rails.logger.info "[Seeds] Created/updated 3 workflow presets: generate_only, generate_thumbnail, generate_process_index"

# -----------------------------------------------------------------------------
# Demo users (idempotent)
# -----------------------------------------------------------------------------
# demo@example.com — sign in on the dashboard to try the UI.
# api@example.com — set API_USER_ID to this user's id when using the .NET gateway.
DEMO_PASSWORD = ENV.fetch("SEED_DEMO_PASSWORD", "demo123")
API_PASSWORD  = ENV.fetch("SEED_API_PASSWORD", "api123")

demo_user = User.find_or_create_by!(email: "demo@example.com") do |u|
  u.password = DEMO_PASSWORD
  u.password_confirmation = DEMO_PASSWORD
end
demo_user.update!(password: DEMO_PASSWORD, password_confirmation: DEMO_PASSWORD) if demo_user.encrypted_password.blank?

api_user = User.find_or_create_by!(email: "api@example.com") do |u|
  u.password = API_PASSWORD
  u.password_confirmation = API_PASSWORD
end
api_user.update!(password: API_PASSWORD, password_confirmation: API_PASSWORD) if api_user.encrypted_password.blank?

Rails.logger.info "[Seeds] Demo users: demo@example.com, api@example.com (set API_USER_ID=#{api_user.id} for gateway)"

# -----------------------------------------------------------------------------
# Demo workflow runs and jobs (idempotent: key by correlation_id so re-seed doesn't duplicate)
# -----------------------------------------------------------------------------
workflow = Workflow.find_by!(slug: "generate_only")
demo_prompts = [
  "a red dragon in the clouds",
  "sunset over mountains",
  "abstract geometric pattern"
]

demo_prompts.each_with_index do |prompt_text, idx|
  correlation_id = "seed_demo_#{idx}"
  run = WorkflowRun.find_or_initialize_by(user: demo_user, correlation_id: correlation_id)
  if run.persisted? && run.generation_job_id.present?
    run.update!(prompt: prompt_text) if run.prompt != prompt_text
    next
  end

  run.assign_attributes(workflow: workflow, prompt: prompt_text, status: "completed")
  run.save!

  job = run.generation_job || demo_user.generation_jobs.create!(
    prompt: prompt_text,
    status: "completed",
    workflow_run_id: run.id,
    started_at: 1.hour.ago,
    completed_at: 1.hour.ago,
    correlation_id: correlation_id
  )
  job.update!(status: "completed", workflow_run_id: run.id) unless job.workflow_run_id == run.id
  run.update!(generation_job_id: job.id)

  # One demo asset with a minimal placeholder image (1x1 PNG)
  if run.asset_id.blank?
    asset = demo_user.assets.create!(
      generation_job_id: job.id,
      filename: "demo_placeholder.png",
      content_type: "image/png",
      byte_size: 68,
      metadata: { "seed" => 42, "model" => "pillow-mvp", "backend" => "pillow_mock" }
    )
    minimal_png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
    asset.file.attach(io: StringIO.new(minimal_png), filename: "demo_placeholder.png", content_type: "image/png")
    run.update!(asset_id: asset.id)
  end
end

Rails.logger.info "[Seeds] Demo workflow runs and assets created (prompts: #{demo_prompts.join(', ')})"
