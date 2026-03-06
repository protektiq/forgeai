# frozen_string_literal: true

class GenerationJob < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze

  belongs_to :user
  belongs_to :workflow_run, optional: true
  has_one :asset, dependent: :nullify

  validates :prompt, presence: true, length: { maximum: 10_000 }
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Used by GenerationPipeline (and OrchestrateWorkflowJob) to mark job failed.
  def mark_failed(message)
    msg = message.to_s.truncate(1000)
    update!(status: "failed", completed_at: Time.current, error_message: msg)
  end
end
