# frozen_string_literal: true

require "open3"

class GenerateAssetJob < ApplicationJob
  queue_as :default

  # Service contract (Python generator):
  #   POST ${GENERATOR_URL}/generate
  #   Body: JSON { "prompt": "..." }
  #   Response: image bytes, Content-Type: image/png (or image/jpeg)
  # C++ media and Rust index: optional CLI commands via MEDIA_SERVICE_COMMAND, INDEX_SERVICE_COMMAND.
  #   Env passed: INPUT_PATH (path to image file), ASSET_ID, PROMPT. Skip step if command blank.

  GENERATOR_PATH = "/generate"
  MAX_ERROR_MESSAGE_LENGTH = 1000

  discard_on(ActiveRecord::RecordNotFound) {}

  def perform(generation_job_id)
    job = GenerationJob.find_by(id: generation_job_id, status: "queued")
    return unless job

    job.update!(status: "running", started_at: Time.current, error_message: nil)

    image_body = call_python_generator(job)
    return if job.reload.status == "failed"

    asset = store_image(job, image_body)
    return if job.reload.status == "failed"

    call_media_service(job, asset)
    return if job.reload.status == "failed"

    call_index_service(job, asset)
    return if job.reload.status == "failed"

    job.update!(status: "completed", completed_at: Time.current, error_message: nil)
  rescue StandardError => e
    job = GenerationJob.find_by(id: generation_job_id) if job.nil?
    mark_failed(job, e.message)
  end

  private

  def call_python_generator(job)
    url = URI.join(Rails.application.config.generator_url, GENERATOR_PATH)
    req = Net::HTTP::Post.new(url)
    req["Content-Type"] = "application/json"
    req.body = { prompt: job.prompt }.to_json

    res = nil
    Net::HTTP.start(url.host, url.port, open_timeout: 10, read_timeout: 60) do |http|
      res = http.request(req)
    end

    unless res.is_a?(Net::HTTPSuccess)
      mark_failed(job, "Generator returned #{res.code}: #{res.message}")
      return nil
    end

    content_type = res["Content-Type"]&.split(";")&.first&.strip.presence || "image/png"
    unless content_type.start_with?("image/")
      mark_failed(job, "Generator returned non-image content type: #{content_type}")
      return nil
    end

    [res.body, content_type]
  rescue StandardError => e
    mark_failed(job, "Generator error: #{e.message}")
    nil
  end

  def store_image(job, image_body_and_content_type)
    return nil unless image_body_and_content_type

    image_body, content_type = image_body_and_content_type
    asset = Asset.new(
      user_id: job.user_id,
      generation_job_id: job.id,
      filename: "generated-#{job.id}.png",
      content_type: content_type,
      byte_size: image_body.bytesize
    )
    asset.file.attach(
      io: StringIO.new(image_body),
      filename: "generated-#{job.id}.png",
      content_type: content_type
    )
    asset.save!
    asset
  rescue StandardError => e
    mark_failed(job, "Store image error: #{e.message}")
    nil
  end

  def call_media_service(job, asset)
    cmd = Rails.application.config.media_service_command.to_s.strip
    return if cmd.blank?

    input_path = nil
    asset.file.blob.open do |file|
      input_path = file.path
      run_external_command(
        job,
        cmd,
        "Media service",
        "INPUT_PATH" => input_path,
        "ASSET_ID" => asset.id.to_s,
        "PROMPT" => job.prompt.to_s
      )
    end
  rescue StandardError => e
    mark_failed(job, "Media service error: #{e.message}")
  end

  def call_index_service(job, asset)
    cmd = Rails.application.config.index_service_command.to_s.strip
    return if cmd.blank?

    run_external_command(
      job,
      cmd,
      "Index service",
      "ASSET_ID" => asset.id.to_s,
      "PROMPT" => job.prompt.to_s
    )
  rescue StandardError => e
    mark_failed(job, "Index service error: #{e.message}")
  end

  def run_external_command(job, command, service_name, env = {})
    full_env = ENV.to_h.merge(env)
    out, err, status = Open3.capture3(full_env, command, stdin_data: nil)
    return if status.success?

    msg = [err.presence, out.presence].compact.join(" ").strip
    msg = "#{service_name} failed (exit #{status.exitstatus})" if msg.blank?
    mark_failed(job, msg)
  end

  def mark_failed(job, message)
    return unless job

    msg = message.to_s.truncate(MAX_ERROR_MESSAGE_LENGTH)
    job.update!(status: "failed", completed_at: Time.current, error_message: msg)
  end
end
