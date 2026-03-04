# frozen_string_literal: true

class JobsController < ApplicationController
  def show
    @job = current_user.generation_jobs.find_by(id: params[:id])
    unless @job
      head :not_found
      return
    end
  end
end
