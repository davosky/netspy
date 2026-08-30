require "rails_helper"

RSpec.describe "Lanscans", type: :request do
  let(:user) { create(:user) }

  describe "GET /lanscans" do
    it "requires authentication" do
      get lanscans_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "lists results and the launch form for a signed in user" do
      sign_in user
      create(:lanscan, ip_address: "10.1.1.5", target: "10.1.1.0/24", open_ports: "22 443")

      get lanscans_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("10.1.1.5")
      expect(response.body).to include("10.1.1.0/24")
      expect(response.body).to include(I18n.t("lanscans.form.title"))
    end

    it "shows the live progress card for the run passed in ?run=" do
      sign_in user
      run = create(:lanscan_run, :running, target: "172.16.0.0/24")

      get lanscans_path(run: run.id)

      expect(response.body).to include("lanscan-progress")
      expect(response.body).to include(lanscan_run_path(run, format: :json))
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

    it "records a run and enqueues the job for it" do
      allow(LanscanJob).to receive(:perform_later)

      expect do
        post run_lanscans_path, params: { target: "192.168.5.0/24", ports: "1-100", timeout: "500" }
      end.to change(LanscanRun, :count).by(1)

      run = LanscanRun.last
      expect(run).to have_attributes(target: "192.168.5.0/24", ports: "1-100", timeout: 500,
                                     status: "pending", user_id: user.id)
      expect(LanscanJob).to have_received(:perform_later).with(run.id)
      expect(response).to redirect_to(lanscans_path(run: run.id))
    end

    it "rejects an invalid target without recording a run or enqueuing anything" do
      allow(LanscanJob).to receive(:perform_later)

      expect do
        post run_lanscans_path, params: { target: "not-a-cidr" }
      end.not_to change(LanscanRun, :count)

      expect(LanscanJob).not_to have_received(:perform_later)
      expect(response).to redirect_to(lanscans_path)
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
