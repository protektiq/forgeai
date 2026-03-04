# frozen_string_literal: true

class CreateGenerationJobs < ActiveRecord::Migration[7.0]
  def change
    create_table :generation_jobs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :prompt, null: false
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :generation_jobs, [:user_id, :created_at]
  end
end
