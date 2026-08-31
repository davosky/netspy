require "rails_helper"

RSpec.describe LanscanJob, type: :job do
  let(:lan) { create(:lan, :primary, lan: "10.0.0.0/24") }
  let(:run) { create(:lanscan_run, lan: lan, target: "10.0.0.0/24", ports: "1-80", timeout: 500) }

  let(:hosts) do
    [
      { ip: "10.0.0.5", mac: "aa:bb:cc:dd:ee:01", open_ports: [ 22, 443 ] },
      { ip: "10.0.0.9", mac: "aa:bb:cc:dd:ee:02", open_ports: [] }
    ]
  end

  it "starts the run, persists one row per reported host, and completes it" do
    allow(LanscanRunner).to receive(:call)
      .and_return(LanscanRunner::Result.new(success: true, hosts: hosts, output: "raw"))

    expect { described_class.perform_now(run.id) }.to change { run.lanscans.count }.by(2)

    expect(LanscanRunner).to have_received(:call).with(lan: lan, run: run)
    expect(run.reload).to have_attributes(status: "completed", hosts_found: 1)
    expect(run.total_probes).to eq(256 * 80)

    row = run.lanscans.find_by(ip_address: "10.0.0.5")
    expect(row).to have_attributes(mac_address: "aa:bb:cc:dd:ee:01", open_ports: "22 443", target: "10.0.0.0/24")
    expect(run.lanscans.find_by(ip_address: "10.0.0.9").open_ports).to be_nil
  end

  it "drops host entries without a valid IP instead of aborting the batch" do
    poisoned = hosts + [ { ip: "not-an-ip", mac: nil, open_ports: [ 8080 ] } ]
    allow(LanscanRunner).to receive(:call)
      .and_return(LanscanRunner::Result.new(success: true, hosts: poisoned, output: "raw"))

    expect { described_class.perform_now(run.id) }.to change { run.lanscans.count }.by(2)
    expect(run.reload.status).to eq("completed")
  end

  it "marks the run failed when the scan did not succeed" do
    allow(LanscanRunner).to receive(:call)
      .and_return(LanscanRunner::Result.new(success: false, hosts: [], output: "boom"))

    described_class.perform_now(run.id)

    expect(run.reload.status).to eq("failed")
    expect(run.error_message).to include("boom")
  end

  it "marks the run failed on invalid parameters" do
    allow(LanscanRunner).to receive(:call).and_raise(LanscanRunner::InvalidParams, "chiave SSH non configurata")

    described_class.perform_now(run.id)

    expect(run.reload).to have_attributes(status: "failed", error_message: "chiave SSH non configurata")
  end

  it "fails a run with no LAN attached without calling the runner" do
    allow(LanscanRunner).to receive(:call)
    orphan = create(:lanscan_run, lan: nil)

    described_class.perform_now(orphan.id)

    expect(orphan.reload.status).to eq("failed")
    expect(LanscanRunner).not_to have_received(:call)
  end
end
