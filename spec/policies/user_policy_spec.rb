require 'rails_helper'

RSpec.describe UserPolicy do
  let(:admin) { create(:user, :admin) }
  let(:member) { create(:user) }
  let(:other) { create(:user) }

  it "lets an admin manage anyone" do
    policy = described_class.new(admin, other)

    expect(policy.show?).to be(true)
    expect(policy.update?).to be(true)
    expect(policy.destroy?).to be(true)
  end

  it "lets a member see and edit only themselves" do
    own = described_class.new(member, member)
    foreign = described_class.new(member, other)

    expect(own.show?).to be(true)
    expect(own.update?).to be(true)
    expect(own.destroy?).to be(false)
    expect(foreign.show?).to be(false)
    expect(foreign.update?).to be(false)
  end

  describe UserPolicy::Scope do
    it "scopes the collection to the current user unless admin" do
      admin
      member
      other

      expect(described_class.new(admin, User.all).resolve).to match_array(User.all)
      expect(described_class.new(member, User.all).resolve).to contain_exactly(member)
      expect(described_class.new(nil, User.all).resolve).to be_empty
    end
  end
end
