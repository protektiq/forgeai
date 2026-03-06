# frozen_string_literal: true

class WorkflowRun < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze

  belongs_to :workflow
  belongs_to :user
  has_many :workflow_run_steps, dependent: :destroy
  belongs_to :asset, optional: true
  belongs_to :generation_job, optional: true

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :prompt, presence: true, length: { maximum: 10_000 }
end
