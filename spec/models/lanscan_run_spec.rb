require "rails_helper"

RSpec.describe LanscanRun, type: :model do
  it "has a valid factory" do
    expect(build(:lanscan_run)).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:target) }
    it { is_expected.to validate_presence_of(:ports) }
    it { is_expected.to validate_presence_of(:timeout) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:lan).optional }
  end

  describe "#elapsed_seconds" do
    it "is 0 before the run starts" do
      expect(build(:lanscan_run, started_at: nil).elapsed_seconds).to eq(0.0)
    end

    it "is frozen at finished_at once the run is done" do
      run = build(:lanscan_run, started_at: Time.utc(2026, 1, 1, 12, 0, 0), finished_at: Time.utc(2026, 1, 1, 12, 0, 37))
      expect(run.elapsed_seconds).to eq(37.0)
    end
  end

  describe "#live_progress" do
    it "reports 100% once completed" do
      run = build(:lanscan_run, :completed, total_probes: 1000)
      expect(run.live_progress).to eq(completed: 1000, total: 1000, percent: 100.0)
    end

    it "reads the progress file while running" do
      run = create(:lanscan_run, :running, total_probes: 1000)
      FileUtils.mkdir_p(run.progress_file_path.dirname)
      File.write(run.progress_file_path, "250 1000\n")

      expect(run.live_progress).to eq(completed: 250, total: 1000, percent: 25.0)
    ensure
      run.cleanup_progress_file
    end

    it "falls back to 0% when the progress file is missing" do
      run = build(:lanscan_run, :running, id: 999_999, total_probes: 1000)
      expect(run.live_progress).to eq(completed: 0, total: 1000, percent: 0.0)
    end
  end

  describe "state transitions" do
    it "#start! marks it running with a probe total" do
      run = create(:lanscan_run)
      run.start!(total_probes: 500)
      expect(run).to have_attributes(status: "running", total_probes: 500)
      expect(run.started_at).to be_present
    end

    it "#complete! records the host count and finish time" do
      run = create(:lanscan_run, :running)
      run.complete!(hosts_found: 7)
      expect(run).to have_attributes(status: "completed", hosts_found: 7)
      expect(run.finished_at).to be_present
    end

    it "#fail! stores a truncated error message" do
      run = create(:lanscan_run, :running)
      run.fail!("x" * 5000)
      expect(run.status).to eq("failed")
      expect(run.error_message.length).to eq(1000)
    end
  end
end
