# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2025_03_06_000005) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", default: "local", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "assets", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "generation_job_id"
    t.string "filename"
    t.string "content_type"
    t.integer "byte_size"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["generation_job_id"], name: "index_assets_on_generation_job_id"
    t.index ["user_id", "created_at"], name: "index_assets_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_assets_on_user_id"
  end

  create_table "generation_jobs", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "prompt", null: false
    t.string "status", default: "queued", null: false
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "correlation_id"
    t.integer "workflow_run_id"
    t.index ["correlation_id"], name: "index_generation_jobs_on_correlation_id"
    t.index ["user_id", "created_at"], name: "index_generation_jobs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_generation_jobs_on_user_id"
    t.index ["workflow_run_id"], name: "index_generation_jobs_on_workflow_run_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workflow_run_steps", force: :cascade do |t|
    t.integer "workflow_run_id", null: false
    t.integer "workflow_step_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "error_message"
    t.json "output", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workflow_run_id", "workflow_step_id"], name: "idx_on_workflow_run_id_workflow_step_id_6b8602b9ec", unique: true
    t.index ["workflow_run_id"], name: "index_workflow_run_steps_on_workflow_run_id"
    t.index ["workflow_step_id"], name: "index_workflow_run_steps_on_workflow_step_id"
  end

  create_table "workflow_runs", force: :cascade do |t|
    t.integer "workflow_id", null: false
    t.integer "user_id", null: false
    t.string "status", default: "queued", null: false
    t.string "prompt", null: false
    t.string "correlation_id"
    t.integer "asset_id"
    t.integer "generation_job_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_workflow_runs_on_asset_id"
    t.index ["correlation_id"], name: "index_workflow_runs_on_correlation_id"
    t.index ["generation_job_id"], name: "index_workflow_runs_on_generation_job_id"
    t.index ["status"], name: "index_workflow_runs_on_status"
    t.index ["user_id", "created_at"], name: "index_workflow_runs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_workflow_runs_on_user_id"
    t.index ["workflow_id"], name: "index_workflow_runs_on_workflow_id"
  end

  create_table "workflow_steps", force: :cascade do |t|
    t.integer "workflow_id", null: false
    t.string "step_type", null: false
    t.integer "execution_order", null: false
    t.json "config", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workflow_id", "execution_order"], name: "index_workflow_steps_on_workflow_id_and_execution_order", unique: true
    t.index ["workflow_id"], name: "index_workflow_steps_on_workflow_id"
  end

  create_table "workflows", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_workflows_on_slug", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "assets", "generation_jobs"
  add_foreign_key "assets", "users"
  add_foreign_key "generation_jobs", "users"
  add_foreign_key "generation_jobs", "workflow_runs"
  add_foreign_key "workflow_run_steps", "workflow_runs"
  add_foreign_key "workflow_run_steps", "workflow_steps"
  add_foreign_key "workflow_runs", "assets"
  add_foreign_key "workflow_runs", "generation_jobs"
  add_foreign_key "workflow_runs", "users"
  add_foreign_key "workflow_runs", "workflows"
  add_foreign_key "workflow_steps", "workflows"
end
