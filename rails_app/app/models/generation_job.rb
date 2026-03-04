# frozen_string_literal: true

class GenerationJob < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze

  belongs_to :user
  has_one :asset, dependent: :nullify

  validates :prompt, presence: true, length: { maximum: 10_000 }
  validates :status, presence: true, inclusion: { in: STATUSES }
end
