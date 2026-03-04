# frozen_string_literal: true

class AddCorrelationIdToGenerationJobs < ActiveRecord::Migration[7.0]
  def change
    add_column :generation_jobs, :correlation_id, :string
    add_index :generation_jobs, :correlation_id
  end
end
