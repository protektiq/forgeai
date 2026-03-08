# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::GenerateController", type: :request do
  # API user is required (BaseController set_api_user!)
  let(:user) { User.first || User.create!(email: "api@test.example.com", password: "password123") }

  before do
    # Ensure default workflow exists for wrapped path
    unless Workflow.exists?(slug: "generate_process_index")
      load Rails.root.join("db/seeds.rb")
    end
    # Ensure we have an API user (config uses User.first in test when API_USER_ID not set)
    user
  end

  describe "POST /api/v1/generate" do
    context "contract: valid request without workflow (wrapped path)" do
      it "returns 201 with job_id and status queued" do
        post "/api/v1/generate", params: { prompt: "a test prompt" }, as: :json
        expect(response).to have_http_status(:created)
        json = response.parsed_body
        expect(json).to have_key("job_id")
        expect(json["status"]).to eq("queued")
      end
    end

    context "contract: valid request with workflow_slug" do
      it "returns 201 with workflow_run_id and status queued" do
        post "/api/v1/generate", params: { prompt: "a test prompt", workflow_slug: "generate_only" }, as: :json
        expect(response).to have_http_status(:created)
        json = response.parsed_body
        expect(json).to have_key("workflow_run_id")
        expect(json["status"]).to eq("queued")
      end
    end

    context "malformed: missing prompt" do
      it "returns 422 with validation error" do
        post "/api/v1/generate", params: {}, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json["error"]["code"]).to eq("validation_error")
      end
    end

    context "malformed: blank prompt" do
      it "returns 422" do
        post "/api/v1/generate", params: { prompt: "   " }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json["error"]["code"]).to eq("validation_error")
      end
    end

    context "malformed: prompt too long" do
      it "returns 422" do
        post "/api/v1/generate", params: { prompt: "x" * 10_001 }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json["error"]["code"]).to eq("validation_error")
      end
    end

    context "malformed: invalid workflow_slug" do
      it "returns 404" do
        post "/api/v1/generate", params: { prompt: "ok", workflow_slug: "nonexistent" }, as: :json
        expect(response).to have_http_status(:not_found)
        json = response.parsed_body
        expect(json["error"]["code"]).to eq("not_found")
      end
    end

    context "malformed: invalid workflow_id" do
      it "returns 404" do
        post "/api/v1/generate", params: { prompt: "ok", workflow_id: 99_999 }, as: :json
        expect(response).to have_http_status(:not_found)
        json = response.parsed_body
        expect(json["error"]["code"]).to eq("not_found")
      end
    end
  end
end
