require 'rails_helper'

RSpec.describe "Admin::Users", type: :request do
  describe "GET /admin/users" do
    it "redirects anonymous visitors to sign in" do
      get admin_users_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "denies a signed in non-admin user" do
      sign_in create(:user)

      get admin_users_path

      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("pundit.not_authorized"))
    end

    it "lets an admin list users" do
      admin = create(:user, :admin)
      create(:user, username: "target")
      sign_in admin

      get admin_users_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("target")
    end
  end

  describe "POST /admin/users" do
    it "creates a user with the submitted password" do
      sign_in create(:user, :admin)

      expect do
        post admin_users_path, params: {
          user: {
            username: "newbie", email: "newbie@example.com", password: "password123",
            first_name: "New", last_name: "Bie", admin: "0", manager: "0", regular: "1"
          }
        }
      end.to change(User, :count).by(1)

      created = User.find_by(username: "newbie")
      expect(created.valid_password?("password123")).to be(true)
      expect(created.regular).to be(true)
    end
  end
end
