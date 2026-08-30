require 'rails_helper'

RSpec.describe "Account::Passwords", type: :request do
  let(:user) { create(:user, password: "password123") }

  describe "GET /account/password/edit" do
    it "requires authentication" do
      get edit_account_password_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "renders for a signed in user" do
      sign_in user

      get edit_account_password_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /account/password" do
    it "updates the password when the current password is correct" do
      sign_in user

      patch account_password_path, params: {
        user: { current_password: "password123", password: "newpassword123", password_confirmation: "newpassword123" }
      }

      expect(response).to redirect_to(edit_account_password_path)
      expect(user.reload.valid_password?("newpassword123")).to be(true)
    end

    it "keeps the session valid after changing the password" do
      sign_in user

      patch account_password_path, params: {
        user: { current_password: "password123", password: "newpassword123", password_confirmation: "newpassword123" }
      }
      follow_redirect!

      expect(response).to have_http_status(:ok)
    end

    it "rejects the update when the current password is wrong" do
      sign_in user

      patch account_password_path, params: {
        user: { current_password: "wrong", password: "newpassword123", password_confirmation: "newpassword123" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.valid_password?("password123")).to be(true)
    end
  end
end
