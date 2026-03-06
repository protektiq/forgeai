# frozen_string_literal: true

class Workflow < ApplicationRecord
  has_many :workflow_steps, dependent: :destroy
  has_many :workflow_runs, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
end
