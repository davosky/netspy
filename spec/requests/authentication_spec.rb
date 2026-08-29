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
    expect(response.body).to include("Nome utente o password non validi")
  end

  it "signs out via DELETE" do
    sign_in user

    delete destroy_user_session_path

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response).to redirect_to(new_user_session_path)
  end
end
