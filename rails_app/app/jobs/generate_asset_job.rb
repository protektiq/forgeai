# frozen_string_literal: true

require "open3"

class GenerateAssetJob < ApplicationJob
  queue_as :default

  # Service contract (Python generator):
  #   POST ${GENERATOR_URL}/generate
  #   Headers: Content-Type: application/json, Accept: application/json
  #   Body: JSON { "prompt": "..." }
  #   Response: JSON { "image_base64", "seed", "model" }; we decode base64 and store generator_metadata on Asset.
  # C++ media: optional HTTP (CPP_MEDIA_URL) or CLI (MEDIA_SERVICE_COMMAND).
  #   HTTP: POST image to /process, attach returned thumbnail (and optionally processed) to Asset.
  #   CLI: Env INPUT_PATH, ASSET_ID, PROMPT; no thumbnail attachment.
  GENERATOR_PATH = "/generate"
  MEDIA_PROCESS_PATH = "/process"
  MAX_ERROR_MESSAGE_LENGTH = 1000
  ALLOWED_IMAGE_CONTENT_TYPES = %w[image/jpeg image/png].freeze

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
    req["Accept"] = "application/json"
    req.body = { prompt: job.prompt }.to_json

    res = nil
    Net::HTTP.start(url.host, url.port, open_timeout: 10, read_timeout: 60) do |http|
      res = http.request(req)
    end

    unless res.is_a?(Net::HTTPSuccess)
      mark_failed(job, "Generator returned #{res.code}: #{res.message}")
      return nil
    end

    content_type = res["Content-Type"]&.split(";")&.first&.strip.presence
    unless content_type&.include?("application/json")
      mark_failed(job, "Generator returned non-JSON content type: #{content_type || 'unknown'}")
      return nil
    end

    data = begin
      JSON.parse(res.body)
    rescue JSON::ParserError => e
      mark_failed(job, "Invalid JSON response: #{e.message}")
      return nil
    end

    unless data.is_a?(Hash) && data["image_base64"].present? && data.key?("seed") && data["model"].present?
      mark_failed(job, "Invalid JSON response: missing image_base64, seed, or model")
      return nil
    end

    image_bytes = begin
      Base64.strict_decode64(data["image_base64"].to_s)
    rescue ArgumentError => e
      mark_failed(job, "Invalid image_base64 in response: #{e.message}")
      return nil
    end

    {
      image_bytes: image_bytes,
      content_type: "image/png",
      seed: data["seed"],
      model: data["model"].to_s
    }
  rescue StandardError => e
    mark_failed(job, "Generator error: #{e.message}")
    nil
  end

  def store_image(job, payload)
    return nil unless payload.is_a?(Hash) && payload[:image_bytes].present?

    image_bytes = payload[:image_bytes]
    content_type = payload[:content_type].presence || "image/png"
    seed = payload[:seed]
    model = payload[:model].to_s.presence

    asset = Asset.new(
      user_id: job.user_id,
      generation_job_id: job.id,
      filename: "generated-#{job.id}.png",
      content_type: content_type,
      byte_size: image_bytes.bytesize
    )
    asset.metadata = {}
    asset.metadata["generator"] = { "seed" => seed, "model" => model } if seed.present? || model.present?

    asset.file.attach(
      io: StringIO.new(image_bytes),
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
    base_url = Rails.application.config.cpp_media_url.presence
    if base_url.present?
      call_media_service_http(job, asset, base_url)
      return
    end

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

  def call_media_service_http(job, asset, base_url)
    process_url = URI.join(base_url, MEDIA_PROCESS_PATH)
    image_bytes = asset.file.blob.download
    body = {
      image_base64: Base64.strict_encode64(image_bytes),
      thumbnail_size: 256,
      resize_max: 1200,
      output_format: "jpg",
      operations: "thumbnail,resize"
    }.to_json

    req = Net::HTTP::Post.new(process_url)
    req["Content-Type"] = "application/json"
    req["Accept"] = "application/json"
    req.body = body

    res = nil
    Net::HTTP.start(process_url.host, process_url.port, open_timeout: 10, read_timeout: 60) do |http|
      res = http.request(req)
    end

    unless res.is_a?(Net::HTTPSuccess)
      mark_failed(job, "Media service returned #{res.code}: #{res.message}")
      return
    end

    data = begin
      JSON.parse(res.body)
    rescue JSON::ParserError => e
      mark_failed(job, "Media service invalid JSON: #{e.message}")
      return
    end

    unless data.is_a?(Hash) && data["thumbnail_base64"].present? && data["thumbnail_content_type"].present?
      mark_failed(job, "Media service response missing thumbnail_base64 or thumbnail_content_type")
      return
    end

    thumb_ct = data["thumbnail_content_type"].to_s.strip
    unless ALLOWED_IMAGE_CONTENT_TYPES.include?(thumb_ct)
      mark_failed(job, "Media service invalid thumbnail_content_type: #{thumb_ct}")
      return
    end

    thumb_bytes = begin
      Base64.strict_decode64(data["thumbnail_base64"].to_s)
    rescue ArgumentError => e
      mark_failed(job, "Media service invalid thumbnail_base64: #{e.message}")
      return
    end

    ext = thumb_ct.include?("png") ? "png" : "jpg"
    asset.thumbnail.attach(
      io: StringIO.new(thumb_bytes),
      filename: "thumb-#{asset.id}.#{ext}",
      content_type: thumb_ct
    )
  rescue StandardError => e
    mark_failed(job, "Media service error: #{e.message}")
  end

  def call_index_service(job, asset)
    base_url = Rails.application.config.index_service_url.presence
    if base_url.present?
      call_index_service_http(job, asset, base_url)
      return
    end

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

  def call_index_service_http(job, asset, base_url)
    index_url = URI.join(base_url, "/index")
    body = {
      asset_id: asset.id.to_s,
      prompt: job.prompt.to_s,
      metadata: asset.metadata || {},
      tags: []
    }.to_json

    req = Net::HTTP::Post.new(index_url)
    req["Content-Type"] = "application/json"
    req["Accept"] = "application/json"
    req.body = body

    res = nil
    Net::HTTP.start(index_url.host, index_url.port, open_timeout: 10, read_timeout: 10) do |http|
      res = http.request(req)
    end

    unless res.is_a?(Net::HTTPSuccess)
      mark_failed(job, "Index service returned #{res.code}: #{res.message}")
    end
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
