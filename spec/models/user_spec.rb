require 'rails_helper'

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  it "has a valid factory" do
    expect(user).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:username) }
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_length_of(:username).is_at_least(3).is_at_most(50) }

    it "requires a unique username, case-insensitively" do
      create(:user, username: "Davo")
      duplicate = build(:user, username: "davo")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:username]).to be_present
    end

    it "rejects usernames with spaces or symbols" do
      user.username = "mario rossi!"
      expect(user).not_to be_valid
    end

    it "requires a password" do
      user.password = user.password_confirmation = nil
      expect(user).not_to be_valid
    end
  end

  describe ".find_for_database_authentication" do
    it "matches the username regardless of case" do
      persisted = create(:user, username: "Davo")

      expect(User.find_for_database_authentication(username: "DAVO")).to eq(persisted)
      expect(User.find_for_database_authentication(username: " davo ")).to eq(persisted)
    end
  end

  describe "#display_name" do
    it "uses the full name when present, otherwise the username" do
      expect(build(:user, first_name: "Ada", last_name: "Byron").display_name).to eq("Ada Byron")
      expect(build(:user, first_name: nil, last_name: nil, username: "ada").display_name).to eq("ada")
    end
  end

  describe "role flags" do
    it "defaults every role flag to false" do
      persisted = create(:user)

      expect(persisted.admin).to be(false)
      expect(persisted.manager).to be(false)
      expect(persisted.regular).to be(false)
    end
  end
end
