require 'rails_helper'

RSpec.describe ApplicationPolicy do
  subject(:policy) { described_class.new(user, :record) }

  let(:actions) { %i[index? show? create? new? update? edit? destroy?] }

  context "with an admin user" do
    let(:user) { build_stubbed(:user, :admin) }

    it "allows every action" do
      expect(actions.map { |a| policy.public_send(a) }).to all(be(true))
    end
  end

  context "with a non-admin user" do
    let(:user) { build_stubbed(:user) }

    it "denies every action" do
      expect(actions.map { |a| policy.public_send(a) }).to all(be(false))
    end
  end

  context "without a user" do
    let(:user) { nil }

    it "denies every action" do
      expect(actions.map { |a| policy.public_send(a) }).to all(be_falsey)
    end
  end

  describe ApplicationPolicy::Scope do
    it "returns all records for an admin and none otherwise" do
      admin = build_stubbed(:user, :admin)
      plain = build_stubbed(:user)

      expect(described_class.new(admin, User.all).resolve).to eq(User.all)
      expect(described_class.new(plain, User.all).resolve).to eq(User.none)
      expect(described_class.new(nil, User.all).resolve).to eq(User.none)
    end
  end
end
