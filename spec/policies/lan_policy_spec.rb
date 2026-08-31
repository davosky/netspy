require "rails_helper"

RSpec.describe LanPolicy do
  let(:admin) { build_stubbed(:user, :admin) }
  let(:member) { build_stubbed(:user) }

  it "lets any authenticated user read, and only admins write" do
    admin_policy = described_class.new(admin, Lan.new)
    member_policy = described_class.new(member, Lan.new)
    anon_policy = described_class.new(nil, Lan.new)

    expect([ member_policy.index?, member_policy.show? ]).to all(be(true))
    expect([ member_policy.create?, member_policy.update?, member_policy.destroy? ]).to all(be(false))
    expect([ admin_policy.create?, admin_policy.update?, admin_policy.destroy? ]).to all(be(true))
    expect([ anon_policy.index?, anon_policy.show? ]).to all(be_falsey)
  end

  describe LanPolicy::Scope do
    it "returns all LANs for any authenticated user and none otherwise" do
      create(:lan, :primary)

      expect(described_class.new(member, Lan.all).resolve).to eq(Lan.all)
      expect(described_class.new(nil, Lan.all).resolve).to eq(Lan.none)
    end
  end
end
