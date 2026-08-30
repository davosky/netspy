require 'rails_helper'

RSpec.describe "Password recovery", type: :request do
  let!(:user) { create(:user, email: "davo@example.com") }

  it "emails reset instructions for a known address" do
    expect do
      post user_password_path, params: { user: { email: user.email } }
    end.to change { ActionMailer::Base.deliveries.count }.by(1)

    expect(response).to redirect_to(new_user_session_path)
    expect(user.reload.reset_password_token).to be_present

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to include(user.email)
    expect(mail.subject).to eq(I18n.t("devise.mailer.reset_password_instructions.subject"))
  end

  it "resets the password with a valid token" do
    token = user.send(:set_reset_password_token)

    put user_password_path, params: {
      user: { reset_password_token: token, password: "newpassword123", password_confirmation: "newpassword123" }
    }

    expect(response).to redirect_to(root_path)
    expect(user.reload.valid_password?("newpassword123")).to be(true)
  end
end
