require "rails_helper"

RSpec.describe "Lanscans", type: :request do
  let(:user) { create(:user) }

  describe "GET /lanscans" do
    it "requires authentication" do
      get lanscans_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "lists results and a LAN picker for a signed in user" do
      sign_in user
      lan = create(:lan, :primary, lan: "10.1.1.0/24")
      create(:lanscan, ip_address: "10.1.1.5", target: "10.1.1.0/24", open_ports: "22 443")

      get lanscans_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("10.1.1.5")
      expect(response.body).to include(I18n.t("lanscans.form.title"))
      expect(response.body).to include('id="lanscan-launch-form"')
      expect(response.body).to include(lan.lan)
    end

    it "shows only the most recent scan's results" do
      sign_in user
      old_run = create(:lanscan_run, :completed, target: "10.2.2.0/24")
      new_run = create(:lanscan_run, :completed, target: "10.3.3.0/24")
      create(:lanscan, lanscan_run: old_run, scanned_at: 2.hours.ago, ip_address: "10.2.2.9")
      create(:lanscan, lanscan_run: new_run, scanned_at: 1.minute.ago, ip_address: "10.3.3.9")

      get lanscans_path

      expect(response.body).to include("10.3.3.9")
      expect(response.body).not_to include("10.2.2.9")
    end

    it "flags the remote client's own row in the results table" do
      sign_in user
      lan = create(:lan, :secondary, lan: "10.4.4.0/24", remote_client_ip: "10.4.4.2")
      run = create(:lanscan_run, :completed, lan: lan, target: lan.lan)
      create(:lanscan, lanscan_run: run, ip_address: "10.4.4.2")
      create(:lanscan, lanscan_run: run, ip_address: "10.4.4.9")

      get lanscans_path
      doc = Capybara.string(response.body)

      expect(doc.find("code", text: "10.4.4.2")[:class]).to include("text-danger", "fst-italic")
      expect(doc.find("code", text: "10.4.4.9")[:class]).to include("text-info")
    end

    it "shows a hint when no LAN is configured" do
      sign_in user

      get lanscans_path

      expect(response.body).to include(I18n.t("lanscans.form.no_lans"))
      expect(response.body).not_to include('id="lanscan-launch-form"')
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

    it "records a run for the chosen LAN and enqueues the job" do
      allow(LanscanJob).to receive(:perform_later)
      lan = create(:lan, :primary, lan: "192.168.5.0/24", ports: "1-100", timeout: 500)

      expect do
        post run_lanscans_path, params: { lan_id: lan.id }
      end.to change(LanscanRun, :count).by(1)

      run = LanscanRun.last
      expect(run).to have_attributes(target: "192.168.5.0/24", ports: "1-100", timeout: 500,
                                     status: "pending", user_id: user.id, lan_id: lan.id)
      expect(LanscanJob).to have_received(:perform_later).with(run.id)
      expect(response).to redirect_to(lanscans_path(run: run.id))
    end

    it "redirects with an alert for an unknown LAN and enqueues nothing" do
      allow(LanscanJob).to receive(:perform_later)

      expect do
        post run_lanscans_path, params: { lan_id: 0 }
      end.not_to change(LanscanRun, :count)

      expect(LanscanJob).not_to have_received(:perform_later)
      expect(response).to redirect_to(lanscans_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("lanscans.run.lan_not_found"))
    end

    it "enqueues a scan for a secondary LAN, deferring SSH to the system config" do
      allow(LanscanJob).to receive(:perform_later)
      stub_const("LanscanRunner::SSH_KEY", nil)
      lan = create(:lan, :secondary, lan: "10.9.9.0/24")

      expect do
        post run_lanscans_path, params: { lan_id: lan.id }
      end.to change(LanscanRun, :count).by(1)

      expect(LanscanJob).to have_received(:perform_later).with(LanscanRun.last.id)
    end

    it "rejects a secondary LAN when a pinned SSH key file is missing" do
      allow(LanscanJob).to receive(:perform_later)
      stub_const("LanscanRunner::SSH_KEY", "/no/such/key")
      lan = create(:lan, :secondary, lan: "10.9.8.0/24")

      expect do
        post run_lanscans_path, params: { lan_id: lan.id }
      end.not_to change(LanscanRun, :count)

      expect(LanscanJob).not_to have_received(:perform_later)
      follow_redirect!
      expect(response.body).to include("chiave SSH non leggibile")
    end

    it "requires authentication" do
      sign_out user

      post run_lanscans_path, params: { lan_id: 1 }

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
