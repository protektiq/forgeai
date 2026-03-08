# frozen_string_literal: true

class WorkflowRunStep < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze

  belongs_to :workflow_run
  belongs_to :workflow_step

  validates :status, presence: true, inclusion: { in: STATUSES }
end
