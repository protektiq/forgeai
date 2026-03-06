# frozen_string_literal: true

class CreateWorkflowRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :workflow_runs do |t|
      t.references :workflow, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.string :prompt, null: false
      t.string :correlation_id
      t.references :asset, null: true, foreign_key: true
      t.references :generation_job, null: true, foreign_key: true

      t.timestamps
    end

    # These two were redundant and caused the crash:
    # add_index :workflow_runs, :user_id 
    # add_index :workflow_runs, :workflow_id

    add_index :workflow_runs, :status
    add_index :workflow_runs, :correlation_id
    add_index :workflow_runs, [:user_id, :created_at]
  end
end