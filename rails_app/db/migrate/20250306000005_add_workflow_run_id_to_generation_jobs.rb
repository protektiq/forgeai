# frozen_string_literal: true

class AddWorkflowRunIdToGenerationJobs < ActiveRecord::Migration[7.2]
  def change
    add_reference :generation_jobs, :workflow_run, null: true, foreign_key: true
  end
end
