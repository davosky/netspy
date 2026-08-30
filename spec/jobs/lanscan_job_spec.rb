require "rails_helper"

RSpec.describe LanscanJob, type: :job do
  it "runs the scanner with the given parameters" do
    allow(LanscanRunner).to receive(:call)
      .and_return(LanscanRunner::Result.new(success: true, output: "ok"))

    described_class.perform_now(target: "10.0.0.0/24", ports: "1-80", timeout: 500)

    expect(LanscanRunner).to have_received(:call).with(target: "10.0.0.0/24", ports: "1-80", timeout: 500)
  end

  it "raises when the scan did not succeed" do
    allow(LanscanRunner).to receive(:call)
      .and_return(LanscanRunner::Result.new(success: false, output: "boom"))

    expect { described_class.perform_now }.to raise_error(/errore/)
  end
end
