require "rails_helper"

RSpec.describe LanscanRunner do
  describe ".defaults" do
    it "exposes the CLI defaults" do
      expect(described_class.defaults).to eq(target: "10.182.1.0/24", ports: "1-1024", timeout: 700)
    end
  end

  describe "#validate!" do
    it "passes with valid parameters" do
      runner = described_class.new(target: "192.168.1.0/24", ports: "1-1024", timeout: 700)
      expect { runner.validate! }.not_to raise_error
    end

    it "rejects a target without a CIDR mask" do
      expect { described_class.new(target: "192.168.1.10").validate! }
        .to raise_error(LanscanRunner::InvalidParams, /CIDR/)
    end

    it "rejects a malformed CIDR" do
      expect { described_class.new(target: "999.1.1.0/24").validate! }
        .to raise_error(LanscanRunner::InvalidParams, /CIDR/)
    end

    it "rejects a non-IPv4 target" do
      expect { described_class.new(target: "fe80::/64").validate! }
        .to raise_error(LanscanRunner::InvalidParams, /IPv4/)
    end

    it "rejects a malformed port range" do
      expect { described_class.new(ports: "80").validate! }
        .to raise_error(LanscanRunner::InvalidParams, /porte/)
    end

    it "rejects ports outside 1-65535" do
      expect { described_class.new(ports: "0-70000").validate! }
        .to raise_error(LanscanRunner::InvalidParams, /1-65535/)
    end

    it "rejects a reversed port range" do
      expect { described_class.new(ports: "1000-100").validate! }
        .to raise_error(LanscanRunner::InvalidParams, /1-65535/)
    end

    it "rejects an out-of-range timeout" do
      expect { described_class.new(timeout: 1).validate! }
        .to raise_error(LanscanRunner::InvalidParams, /timeout/)
    end

    it "raises when the binary is missing" do
      allow(File).to receive(:executable?).with(described_class::BIN_PATH).and_return(false)
      expect { described_class.new.validate! }
        .to raise_error(LanscanRunner::InvalidParams, /eseguibile/)
    end
  end

  describe "#call" do
    let(:status) { instance_double(Process::Status, success?: true, exitstatus: 0) }

    before do
      allow(FileUtils).to receive(:mkdir_p)
      allow(Open3).to receive(:capture2e).and_return([ "scan output", status ])
    end

    it "invokes the binary with the resolved argv and the DB environment" do
      described_class.call(target: "10.0.0.0/30", ports: "20-25", timeout: 300)

      expect(Open3).to have_received(:capture2e) do |env, bin, *args, **kwargs|
        expect(bin).to eq(described_class::BIN_PATH)
        expect(args).to include("-target", "10.0.0.0/30", "-ports", "20-25", "-timeout", "300")
        expect(args).to include("-table", "lanscans")
        expect(args).to include("-log-dir", described_class::LOG_DIR.to_s)
        expect(env).to include("PGDATABASE", "PGUSER", "PGSSLMODE" => "prefer")
        expect(kwargs[:chdir]).to eq(Rails.root.to_s)
      end
    end

    it "returns a successful result" do
      result = described_class.call
      expect(result.success).to be(true)
      expect(result.output).to eq("scan output")
    end

    it "reports failure when the process exits non-zero" do
      allow(status).to receive(:success?).and_return(false)
      expect(described_class.call.success).to be(false)
    end
  end
end
