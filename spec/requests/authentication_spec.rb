require 'rails_helper'

RSpec.describe "Authentication", type: :request do
  let!(:user) { create(:user, username: "Davo", password: "password123") }

  it "signs in with the username (case-insensitively) and password" do
    post user_session_path, params: {
      user: { username: "davo", password: "password123" }
    }

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "rejects sign in attempts that use the email address" do
    post user_session_path, params: {
      user: { username: user.email, password: "password123" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("devise.sessions.new.sign_in"))
    expect(response.body).not_to include("Nome utente o password non validi")
  end

  it "signs out via DELETE" do
    sign_in user

    delete destroy_user_session_path

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response).to redirect_to(new_user_session_path)
  end

  describe "account locking" do
    def attempt_wrong_password
      post user_session_path, params: { user: { username: user.username, password: "wrong" } }
    end

    it "locks the account after 3 failed attempts and blocks a correct password afterwards" do
      3.times { attempt_wrong_password }

      expect(user.reload.access_locked?).to be(true)

      post user_session_path, params: { user: { username: user.username, password: "password123" } }

      expect(response).not_to redirect_to(root_path)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "does not lock the account before the 3rd failed attempt" do
      2.times { attempt_wrong_password }

      expect(user.reload.access_locked?).to be(false)
    end
  end
end
