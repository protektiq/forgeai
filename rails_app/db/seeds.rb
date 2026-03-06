# frozen_string_literal: true

# Seed default workflow presets. Idempotent: use find_or_create_by! on slug,
# then replace steps so re-running seed yields the same presets.
# Run with: bin/rails db:seed

def seed_workflow(slug:, name:, description: nil, steps:)
  w = Workflow.find_or_create_by!(slug: slug) do |workflow|
    workflow.name = name
    workflow.description = description
  end
  w.update!(name: name, description: description)

  w.workflow_steps.destroy_all
  steps.each do |step_type, execution_order, config|
    config ||= {}
    w.workflow_steps.create!(step_type: step_type, execution_order: execution_order, config: config)
  end
end

seed_workflow(
  slug: "generate_only",
  name: "Generate only",
  description: "Generate image and store; no thumbnail or index",
  steps: [
    ["generate", 1, {}],
    ["store", 2, {}]
  ]
)

seed_workflow(
  slug: "generate_thumbnail",
  name: "Generate + thumbnail",
  description: "Generate, store, and create thumbnail; no index",
  steps: [
    ["generate", 1, {}],
    ["store", 2, {}],
    ["thumbnail", 3, { "thumbnail_size" => 256, "resize_max" => 1200 }]
  ]
)

seed_workflow(
  slug: "generate_process_index",
  name: "Generate + process + index",
  description: "Full pipeline: generate, store, thumbnail, and index",
  steps: [
    ["generate", 1, {}],
    ["store", 2, {}],
    ["thumbnail", 3, { "thumbnail_size" => 256, "resize_max" => 1200 }],
    ["index", 4, {}]
  ]
)

Rails.logger.info "[Seeds] Created/updated 3 workflow presets: generate_only, generate_thumbnail, generate_process_index"
