require "rails_helper"

RSpec.describe "Admin::Lans", type: :request do
  describe "GET /admin/lans" do
    it "redirects anonymous visitors to sign in" do
      get admin_lans_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "denies a signed in non-admin user" do
      sign_in create(:user)

      get admin_lans_path

      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("pundit.not_authorized"))
    end

    it "lets an admin browse configured LANs" do
      sign_in create(:user, :admin)
      create(:lan, :secondary, lan: "10.55.0.0/24")

      get admin_lans_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("10.55.0.0/24")
    end
  end

  describe "admin CRUD pages" do
    before { sign_in create(:user, :admin) }

    it "renders new / show / edit" do
      lan = create(:lan, :secondary, lan: "10.66.0.0/24")

      get new_admin_lan_path
      expect(response).to have_http_status(:ok)

      get admin_lan_path(lan)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("10.66.0.0/24")

      get edit_admin_lan_path(lan)
      expect(response).to have_http_status(:ok)
    end

    it "creates a secondary LAN" do
      expect do
        post admin_lans_path, params: { lan: {
          lan: "10.77.0.0/24", ports: "1-1024", timeout: 600,
          primary: "0", secondary: "1", remote_client_ip: "10.77.0.2", remote_user: "netspy"
        } }
      end.to change(Lan, :count).by(1)

      expect(Lan.last).to have_attributes(lan: "10.77.0.0/24", secondary: true, remote_user: "netspy")
    end
  end
end
