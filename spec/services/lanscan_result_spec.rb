require "rails_helper"

RSpec.describe LanscanResult do
  let(:json) do
    <<~JSON
      {
        "target": "192.168.1.0/24",
        "ports": "1-1024",
        "started_at": "2026-08-31T10:00:00Z",
        "finished_at": "2026-08-31T10:00:12Z",
        "hosts_alive": 2,
        "hosts": [
          {"ip": "192.168.1.10", "mac": "aa:bb:cc:dd:ee:ff", "open_ports": [22, 80]},
          {"ip": "192.168.1.20", "open_ports": []}
        ]
      }
    JSON
  end

  describe ".parse" do
    it "returns a normalised report" do
      report = described_class.parse(json)

      expect(report.target).to eq("192.168.1.0/24")
      expect(report.hosts_alive).to eq(2)
      expect(report.hosts).to eq(
        [
          { ip: "192.168.1.10", mac: "aa:bb:cc:dd:ee:ff", open_ports: [ 22, 80 ] },
          { ip: "192.168.1.20", mac: nil, open_ports: [] }
        ]
      )
    end

    it "raises on unparseable output" do
      expect { described_class.parse("not json") }.to raise_error(described_class::MalformedOutput)
    end

    it "raises with the scanner's message on an error payload" do
      expect { described_class.parse('{"error": "subnet troppo ampia"}') }
        .to raise_error(described_class::MalformedOutput, /troppo ampia/)
    end

    it "sanitises a bogus MAC to nil and clamps/dedupes ports" do
      json = '{"hosts":[{"ip":"10.0.0.5","mac":"<script>","open_ports":[22,22,80,0,999999]}]}'
      host = described_class.parse(json).hosts.first

      expect(host[:mac]).to be_nil
      expect(host[:open_ports]).to eq([ 22, 80 ])
    end
  end

  describe ".error_message" do
    it "extracts the error field when present" do
      expect(described_class.error_message('{"error": "boom"}')).to eq("boom")
    end

    it "is nil for a normal report or garbage" do
      expect(described_class.error_message(json)).to be_nil
      expect(described_class.error_message("xxx")).to be_nil
    end
  end
end
