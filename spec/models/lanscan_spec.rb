require "rails_helper"

RSpec.describe Lanscan, type: :model do
  it "has a valid factory" do
    expect(build(:lanscan)).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:scanned_at) }
    it { is_expected.to validate_presence_of(:target) }
    it { is_expected.to validate_presence_of(:ip_address) }
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
    it ".recent orders by scanned_at desc, then ip_address asc" do
      run_at = 1.hour.ago.change(usec: 0)
      old = create(:lanscan, scanned_at: 2.hours.ago, ip_address: "10.0.0.9")
      new_b = create(:lanscan, scanned_at: run_at, ip_address: "10.0.0.20")
      new_a = create(:lanscan, scanned_at: run_at, ip_address: "10.0.0.10")

      expect(described_class.recent).to eq([ new_a, new_b, old ])
    end

    it ".for_run returns only the rows of that run" do
      run_at = 1.hour.ago.change(usec: 0)
      mine = create(:lanscan, scanned_at: run_at)
      create(:lanscan, scanned_at: 2.hours.ago)

      expect(described_class.for_run(run_at)).to contain_exactly(mine)
    end
  end
end
