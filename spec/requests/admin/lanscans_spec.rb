require "rails_helper"

RSpec.describe "Admin::Lanscans", type: :request do
  describe "GET /admin/lanscans" do
    it "redirects anonymous visitors to sign in" do
      get admin_lanscans_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "denies a signed in non-admin user" do
      sign_in create(:user)

      get admin_lanscans_path

      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("pundit.not_authorized"))
    end

    it "lets an admin browse scan results" do
      sign_in create(:user, :admin)
      create(:lanscan, ip_address: "10.5.5.5")

      get admin_lanscans_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("10.5.5.5")
    end
  end
end
