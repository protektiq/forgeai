# frozen_string_literal: true

class WorkflowStep < ApplicationRecord
  STEP_TYPES = %w[generate thumbnail process index].freeze

  belongs_to :workflow

  validates :step_type, presence: true, inclusion: { in: STEP_TYPES }
  validates :execution_order, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :execution_order, uniqueness: { scope: :workflow_id }
end
