# frozen_string_literal: true

class UseQueuedStatusForWorkflowRunSteps < ActiveRecord::Migration[7.2]
  def up
    # Backfill existing rows: pending -> queued
    execute <<-SQL.squish
      UPDATE workflow_run_steps SET status = 'queued' WHERE status = 'pending'
    SQL
    change_column_default :workflow_run_steps, :status, from: "pending", to: "queued"
  end

  def down
    change_column_default :workflow_run_steps, :status, from: "queued", to: "pending"
    execute <<-SQL.squish
      UPDATE workflow_run_steps SET status = 'pending' WHERE status = 'queued'
    SQL
  end
end
