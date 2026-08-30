require 'rails_helper'

RSpec.describe "Pages", type: :request do
  describe "GET /" do
    it "redirects anonymous visitors to the sign in page" do
      get root_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "renders the landing page for a signed in user" do
      sign_in create(:user)

      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("main/main-logo")
      expect(response.body).to include(I18n.t("pages.index.description"))
    end
  end

  describe "GET /credits" do
    it "requires authentication" do
      get credits_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "renders the credits page for a signed in user" do
      sign_in create(:user)

      get credits_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.credits.author"))
      expect(response.body).to include(NetSpy::Version::NUMBER)
    end
  end
end
