# frozen_string_literal: true

class AlignGenerationJobStatuses < ActiveRecord::Migration[7.0]
  def up
    # Map legacy statuses to new state machine
    execute "UPDATE generation_jobs SET status = 'queued' WHERE status = 'pending'"
    execute "UPDATE generation_jobs SET status = 'running' WHERE status = 'processing'"
    change_column_default :generation_jobs, :status, from: "pending", to: "queued"
  end

  def down
    change_column_default :generation_jobs, :status, from: "queued", to: "pending"
    execute "UPDATE generation_jobs SET status = 'pending' WHERE status = 'queued'"
    execute "UPDATE generation_jobs SET status = 'processing' WHERE status = 'running'"
  end
end
