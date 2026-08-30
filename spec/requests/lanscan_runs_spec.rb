require "rails_helper"

RSpec.describe "LanscanRuns", type: :request do
  let(:user) { create(:user) }

  describe "GET /lanscan_runs/:id" do
    it "requires authentication" do
      run = create(:lanscan_run)

      get lanscan_run_path(run)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "returns a progress snapshot as JSON" do
      sign_in user
      run = create(:lanscan_run, :completed, total_probes: 1000, hosts_found: 3)

      get lanscan_run_path(run, format: :json)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["status"]).to eq("completed")
      expect(body["percent"]).to eq(100.0)
      expect(body["hosts_found"]).to eq(3)
      expect(body["elapsed"]).to be_a(Numeric)
    end
  end
end
