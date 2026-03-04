# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :generation_jobs, dependent: :destroy
  has_many :assets, dependent: :destroy
end
