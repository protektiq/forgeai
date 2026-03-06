# frozen_string_literal: true

class CreateWorkflowSteps < ActiveRecord::Migration[7.2]
  def change
    create_table :workflow_steps do |t|
      t.references :workflow, null: false, foreign_key: true
      t.string :step_type, null: false
      t.integer :execution_order, null: false
      t.json :config, default: {}

      t.timestamps
    end

    add_index :workflow_steps, [:workflow_id, :execution_order], unique: true
  end
end
