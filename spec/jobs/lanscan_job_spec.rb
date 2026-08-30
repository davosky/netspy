require "rails_helper"

RSpec.describe LanscanJob, type: :job do
  let(:run) { create(:lanscan_run, target: "10.0.0.0/24", ports: "1-80", timeout: 500) }

  it "starts the run, scans, and marks it completed with the host count" do
    allow(LanscanRunner).to receive(:call)
      .and_return(LanscanRunner::Result.new(success: true, output: "ok"))
    create(:lanscan, lanscan_run: run)

    described_class.perform_now(run.id)

    expect(LanscanRunner).to have_received(:call)
      .with(target: "10.0.0.0/24", ports: "1-80", timeout: 500, run: run)
    expect(run.reload).to have_attributes(status: "completed", hosts_found: 1)
    expect(run.total_probes).to eq(256 * 80)
  end

  it "marks the run failed when the scan did not succeed" do
    allow(LanscanRunner).to receive(:call)
      .and_return(LanscanRunner::Result.new(success: false, output: "boom"))

    described_class.perform_now(run.id)

    expect(run.reload.status).to eq("failed")
    expect(run.error_message).to include("boom")
  end

  it "marks the run failed on invalid parameters" do
    allow(LanscanRunner).to receive(:call).and_raise(LanscanRunner::InvalidParams, "target CIDR non valido")

    described_class.perform_now(run.id)

    expect(run.reload).to have_attributes(status: "failed", error_message: "target CIDR non valido")
  end
end
