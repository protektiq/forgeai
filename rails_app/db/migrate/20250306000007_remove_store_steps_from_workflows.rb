# frozen_string_literal: true

class RemoveStoreStepsFromWorkflows < ActiveRecord::Migration[7.2]
  def up
    # Delete run steps that reference a "store" workflow step
    execute <<-SQL.squish
      DELETE FROM workflow_run_steps
      WHERE workflow_step_id IN (SELECT id FROM workflow_steps WHERE step_type = 'store')
    SQL
    # Delete "store" workflow steps
    execute <<-SQL.squish
      DELETE FROM workflow_steps WHERE step_type = 'store'
    SQL
    # Renumber execution_order per workflow so orders are contiguous (0, 1, 2, ...)
    Workflow.find_each do |workflow|
      workflow.workflow_steps.order(:execution_order).each_with_index do |step, idx|
        step.update_column(:execution_order, idx)
      end
    end
  end

  def down
    # Cannot restore deleted store steps; no-op.
  end
end
