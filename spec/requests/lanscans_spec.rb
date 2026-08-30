require "rails_helper"

RSpec.describe "Lanscans", type: :request do
  let(:user) { create(:user) }

  describe "GET /lanscans" do
    it "requires authentication" do
      get lanscans_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "lists results for a signed in user" do
      sign_in user
      create(:lanscan, ip_address: "10.1.1.5", target: "10.1.1.0/24", open_ports: "22 443")

      get lanscans_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("10.1.1.5")
      expect(response.body).to include("10.1.1.0/24")
    end
  end

  describe "GET /lanscans/:id" do
    it "shows a single result" do
      sign_in user
      lanscan = create(:lanscan, ip_address: "10.9.9.9")

      get lanscan_path(lanscan)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("10.9.9.9")
    end
  end

  describe "POST /lanscans/run" do
    before { sign_in user }

    it "enqueues a scan job with the submitted parameters" do
      allow(LanscanJob).to receive(:perform_later)

      post run_lanscans_path, params: { target: "192.168.5.0/24", ports: "1-100", timeout: "500" }

      expect(LanscanJob).to have_received(:perform_later)
        .with(target: "192.168.5.0/24", ports: "1-100", timeout: "500")
      expect(response).to redirect_to(lanscans_path)
    end

    it "rejects an invalid target without enqueuing anything" do
      allow(LanscanJob).to receive(:perform_later)

      post run_lanscans_path, params: { target: "not-a-cidr" }

      expect(LanscanJob).not_to have_received(:perform_later)
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response.body).to include("CIDR")
    end

    it "requires authentication" do
      sign_out user

      post run_lanscans_path, params: { target: "192.168.5.0/24" }

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
