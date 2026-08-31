require "rails_helper"
require "tempfile"
require "stringio"

RSpec.describe LanscanRunner do
  let(:report_json) do
    JSON.generate(
      target: "10.0.0.0/30", ports: "20-25",
      started_at: "2026-08-31T10:00:00Z", finished_at: "2026-08-31T10:00:01Z",
      hosts_alive: 1,
      hosts: [ { ip: "10.0.0.1", mac: "aa:bb:cc:dd:ee:ff", open_ports: [ 22 ] } ]
    )
  end
  let(:ok_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }

  describe ".probe_count" do
    it "is hosts * ports" do
      expect(described_class.probe_count(target: "10.0.0.0/24", ports: "1-100")).to eq(256 * 100)
    end

    it "is 0 for garbage input" do
      expect(described_class.probe_count(target: "nope", ports: "x")).to eq(0)
    end
  end

  describe ".validate_cidr!" do
    it "accepts an IPv4 network within the host cap" do
      expect { described_class.validate_cidr!("192.168.1.0/24") }.not_to raise_error
      expect { described_class.validate_cidr!("192.168.1.42/24") }.not_to raise_error
    end

    it "rejects a missing mask, bad prefix, non-IPv4 and oversized subnets" do
      expect { described_class.validate_cidr!("192.168.1.10") }.to raise_error(described_class::InvalidParams, /CIDR/)
      expect { described_class.validate_cidr!("10.0.0.0/40") }.to raise_error(described_class::InvalidParams, /prefisso/)
      expect { described_class.validate_cidr!("fe80::/64") }.to raise_error(described_class::InvalidParams, /IPv4/)
      expect { described_class.validate_cidr!("10.0.0.0/12") }.to raise_error(described_class::InvalidParams, /troppo ampia/)
    end
  end

  describe ".validate_ports!" do
    it "accepts FROM-TO within 1..65535" do
      expect { described_class.validate_ports!("1-1024") }.not_to raise_error
    end

    it "rejects malformed, out-of-range and reversed ranges" do
      expect { described_class.validate_ports!("80") }.to raise_error(described_class::InvalidParams)
      expect { described_class.validate_ports!("0-70000") }.to raise_error(described_class::InvalidParams, /1-65535/)
      expect { described_class.validate_ports!("1000-100") }.to raise_error(described_class::InvalidParams, /1-65535/)
    end
  end

  describe "#validate!" do
    it "passes for a primary LAN with the binary present" do
      allow(File).to receive(:executable?).and_return(true)
      expect { described_class.new(lan: build(:lan, :primary)).validate! }.not_to raise_error
    end

    it "raises when the local binary is missing" do
      allow(File).to receive(:executable?).and_return(false)
      expect { described_class.new(lan: build(:lan, :primary)).validate! }
        .to raise_error(described_class::InvalidParams, /eseguibile/)
    end

    it "does not require any SSH env for a well-formed secondary LAN" do
      stub_const("#{described_class}::SSH_KEY", nil)
      stub_const("#{described_class}::SSH_KNOWN_HOSTS", nil)
      expect { described_class.new(lan: build(:lan, :secondary)).validate! }.not_to raise_error
    end

    it "rejects a secondary LAN with a bad remote user or non-IPv4 client" do
      expect { described_class.new(lan: build(:lan, :secondary, remote_user: "bad user")).validate! }
        .to raise_error(described_class::InvalidParams, /utente remoto/)
      expect { described_class.new(lan: build(:lan, :secondary, remote_client_ip: "nope")).validate! }
        .to raise_error(described_class::InvalidParams, /IPv4/)
    end

    it "raises when a pinned SSH key file is unreadable" do
      stub_const("#{described_class}::SSH_KEY", "/no/such/key")
      expect { described_class.new(lan: build(:lan, :secondary)).validate! }
        .to raise_error(described_class::InvalidParams, /chiave SSH non leggibile/)
    end

    it "raises on a binpath carrying shell metacharacters" do
      lan = build(:lan, :primary)
      lan.binpath = "lanscan; reboot"
      expect { described_class.new(lan: lan).validate! }
        .to raise_error(described_class::InvalidParams, /percorso eseguibile/)
    end

    it "raises without a LAN" do
      expect { described_class.new(lan: nil).validate! }
        .to raise_error(described_class::InvalidParams, /nessuna LAN/)
    end
  end

  describe "#call (local / primary LAN)" do
    let(:lan) { build(:lan, :primary, lan: "10.0.0.0/30", ports: "20-25", timeout: 300) }

    before do
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:executable?).and_return(true)
      allow(Open3).to receive(:capture3).and_return([ report_json, "", ok_status ])
    end

    it "runs the committed binary with a JSON-format argv and no DB env" do
      described_class.call(lan: lan)

      expect(Open3).to have_received(:capture3) do |bin, *args, **kwargs|
        expect(bin).to eq(described_class::BIN_PATH)
        expect(args).to include("-target", "10.0.0.0/30", "-ports", "20-25", "-timeout", "300")
        expect(args).to include("-format", "json")
        expect(args).not_to include("-table", "-run-id")
        expect(kwargs[:chdir]).to eq(Rails.root.to_s)
      end
    end

    it "uses the LAN's binpath override when set" do
      lan.binpath = "/opt/netspy/lanscan"
      described_class.call(lan: lan)
      expect(Open3).to have_received(:capture3).with("/opt/netspy/lanscan", any_args)
    end

    it "returns the parsed hosts on success" do
      result = described_class.call(lan: lan)
      expect(result.success).to be(true)
      expect(result.hosts).to eq([ { ip: "10.0.0.1", mac: "aa:bb:cc:dd:ee:ff", open_ports: [ 22 ] } ])
    end

    it "passes -progress-file when given a run" do
      run = create(:lanscan_run, lan: lan)
      described_class.call(lan: lan, run: run)
      expect(Open3).to have_received(:capture3) do |_bin, *args, **_kwargs|
        expect(args).to include("-progress-file", run.progress_file_path.to_s)
      end
    end

    it "reports failure and surfaces the scanner error on a non-zero exit" do
      allow(Open3).to receive(:capture3).and_return([ '{"error":"subnet troppo ampia"}', "", instance_double(Process::Status, success?: false, exitstatus: 1) ])
      result = described_class.call(lan: lan)
      expect(result.success).to be(false)
      expect(result.output).to eq("subnet troppo ampia")
    end

    it "reports failure on malformed output" do
      allow(Open3).to receive(:capture3).and_return([ "garbage", "", ok_status ])
      expect(described_class.call(lan: lan).success).to be(false)
    end
  end

  describe "#call (remote / secondary LAN)" do
    let(:lan) { build(:lan, :secondary, lan: "10.9.0.0/24", ports: "1-1024", timeout: 600, remote_user: "netspy", remote_client_ip: "10.20.30.40") }
    let(:run) { create(:lanscan_run, lan: lan) }

    before do
      allow(FileUtils).to receive(:mkdir_p)
      stub_const("#{described_class}::SSH_KEY", nil)
      stub_const("#{described_class}::SSH_KNOWN_HOSTS", nil)
      allow(Open3).to receive(:popen3)
        .and_yield(instance_double(IO, close: nil),
                   StringIO.new(report_json),
                   StringIO.new("PROGRESS 120 240\nboot\n"),
                   instance_double(Process::Waiter, value: ok_status))
    end

    it "runs plain `ssh user@host lanscan …`, deferring to the user's SSH config" do
      described_class.call(lan: lan, run: run)

      expect(Open3).to have_received(:popen3) do |*argv|
        expect(argv.first).to eq("ssh")
        expect(argv).to include("-o", "BatchMode=yes")
        expect(argv).not_to include("-i")
        expect(argv).not_to include(a_string_starting_with("UserKnownHostsFile="))
        expect(argv).to include("netspy@10.20.30.40", "lanscan", "-target", "10.9.0.0/24", "-format", "json")
        expect(argv).not_to include("-progress-file")
      end
    end

    it "pins -i and UserKnownHostsFile only when the ENV overrides are set" do
      key = Tempfile.new("lanscan_key")
      stub_const("#{described_class}::SSH_KEY", key.path)
      stub_const("#{described_class}::SSH_KNOWN_HOSTS", "/etc/netspy/known_hosts")

      described_class.call(lan: lan, run: run)

      expect(Open3).to have_received(:popen3) do |*argv|
        expect(argv).to include("-i", key.path, "-o", "IdentitiesOnly=yes")
        expect(argv).to include("-o", "UserKnownHostsFile=/etc/netspy/known_hosts")
      end
    ensure
      key.close!
    end

    it "mirrors PROGRESS lines from stderr into the run's progress file" do
      described_class.call(lan: lan, run: run)
      expect(File.read(run.progress_file_path)).to eq("120 240\n")
    end

    it "parses the JSON report from stdout" do
      result = described_class.call(lan: lan, run: run)
      expect(result.success).to be(true)
      expect(result.hosts.first[:ip]).to eq("10.0.0.1")
    end
  end
end
