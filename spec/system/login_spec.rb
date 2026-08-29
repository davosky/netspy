require 'rails_helper'

RSpec.describe "Login", type: :system do
  before { driven_by(:rack_test) }

  it "signs a user in from the login screen and shows the landing page" do
    create(:user, username: "davo", password: "password123", first_name: "Davo", last_name: "Davosky")

    visit new_user_session_path
    fill_in User.human_attribute_name(:username), with: "davo"
    fill_in User.human_attribute_name(:password), with: "password123"
    click_button I18n.t("devise.sessions.new.sign_in")

    expect(page).to have_content(I18n.t("pages.index.description"))
    expect(page).to have_link(I18n.t("layouts.navbar.credits"))
  end

  it "shows an error for wrong credentials" do
    visit new_user_session_path
    fill_in User.human_attribute_name(:username), with: "ghost"
    fill_in User.human_attribute_name(:password), with: "nope"
    click_button I18n.t("devise.sessions.new.sign_in")

    expect(page).to have_content("Nome utente o password non validi")
  end
end
