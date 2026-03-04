# frozen_string_literal: true

class Asset < ApplicationRecord
  has_one_attached :file

  belongs_to :user
  belongs_to :generation_job, optional: true

  validates :user_id, presence: true
end
