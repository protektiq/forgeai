# frozen_string_literal: true

class CreateWorkflowRunSteps < ActiveRecord::Migration[7.2]
  def change
    create_table :workflow_run_steps do |t|
      t.references :workflow_run, null: false, foreign_key: true
      t.references :workflow_step, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.json :output, default: {}

      t.timestamps
    end

    add_index :workflow_run_steps, [:workflow_run_id, :workflow_step_id], unique: true
  end
end
