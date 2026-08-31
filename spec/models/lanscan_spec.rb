require "rails_helper"

RSpec.describe Lanscan, type: :model do
  it "has a valid factory" do
    expect(build(:lanscan)).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:scanned_at) }
    it { is_expected.to validate_presence_of(:target) }
    it { is_expected.to validate_presence_of(:ip_address) }

    it "requires ip_address to be a real IPv4/IPv6 address" do
      expect(build(:lanscan, ip_address: "10.0.0.5")).to be_valid
      expect(build(:lanscan, ip_address: "fe80::1")).to be_valid
      expect(build(:lanscan, ip_address: "not-an-ip")).not_to be_valid
      expect(build(:lanscan, ip_address: "10.0.0.5; DROP TABLE lanscans")).not_to be_valid
      expect(build(:lanscan, ip_address: "999.0.0.1")).not_to be_valid
    end

    it "accepts a blank MAC but rejects a malformed one" do
      expect(build(:lanscan, :no_mac)).to be_valid
      expect(build(:lanscan, mac_address: "aa:bb:cc:dd:ee:ff")).to be_valid
      expect(build(:lanscan, mac_address: "<script>")).not_to be_valid
    end
  end

  describe "#open_ports_list" do
    it "splits the space-separated ports into integers" do
      expect(build(:lanscan, open_ports: "22 80 443").open_ports_list).to eq([ 22, 80, 443 ])
    end

    it "returns an empty array when no ports are stored" do
      expect(build(:lanscan, open_ports: nil).open_ports_list).to eq([])
    end
  end

  describe "scopes" do
    it ".recent orders by scanned_at desc, then by IP numerically (not lexically)" do
      run_at = 1.hour.ago.change(usec: 0)
      old = create(:lanscan, scanned_at: 2.hours.ago, ip_address: "10.0.0.9")
      high = create(:lanscan, scanned_at: run_at, ip_address: "10.0.0.100")
      low = create(:lanscan, scanned_at: run_at, ip_address: "10.0.0.2")

      # Lexically "10.0.0.100" < "10.0.0.2"; the inet cast must put .2 first.
      expect(described_class.recent).to eq([ low, high, old ])
    end

    it ".for_run returns only the rows of that run" do
      run_at = 1.hour.ago.change(usec: 0)
      mine = create(:lanscan, scanned_at: run_at)
      create(:lanscan, scanned_at: 2.hours.ago)

      expect(described_class.for_run(run_at)).to contain_exactly(mine)
    end
  end
end
