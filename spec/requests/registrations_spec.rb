require 'rails_helper'

RSpec.describe "Self-registration", type: :request do
  it "has no sign up route" do
    get "/users/sign_up"

    expect(response).to have_http_status(:not_found)
  end

  it "does not let a visitor create a user via the Devise registrations endpoint" do
    expect do
      post "/users", params: { user: { username: "newbie", email: "newbie@example.com", password: "password123" } }
    end.not_to change(User, :count)

    expect(response).to have_http_status(:not_found)
  end
end
