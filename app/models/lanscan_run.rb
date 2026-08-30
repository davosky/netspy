# A single scan launched from the UI. Tracks status, timing and progress so the
# page can show a live progress bar and, at the end, the elapsed time. The
# per-host results are `Lanscan` rows linked back via `lanscan_run_id`.
class LanscanRun < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  belongs_to :user, optional: true
  has_many :lanscans, dependent: :nullify

  validates :target, :ports, :timeout, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :in_progress, -> { where(status: %w[pending running]) }

  def start!(total_probes:)
    update!(status: "running", started_at: Time.current, total_probes:)
  end

  def complete!(hosts_found:)
    update!(status: "completed", finished_at: Time.current, hosts_found:)
  end

  def fail!(message)
    update!(status: "failed", finished_at: Time.current, error_message: message.to_s.last(1000))
  end

  def finished?
    status.in?(%w[completed failed])
  end

  # Seconds since the scan started (frozen once it finishes).
  def elapsed_seconds
    return 0.0 unless started_at

    ((finished_at || Time.current) - started_at).round(1)
  end

  def progress_file_path
    LanscanRunner::LOG_DIR.join("run-#{id}.progress")
  end

  def cleanup_progress_file
    File.delete(progress_file_path) if File.exist?(progress_file_path)
  end

  # { completed:, total:, percent: } — live from the file the Go binary writes,
  # or the terminal state once the run is done.
  def live_progress
    return terminal_progress if finished?

    progress_from_file || { completed: 0, total: total_probes.to_i, percent: 0.0 }
  end

  private

  def terminal_progress
    total = total_probes.to_i
    { completed: total, total: total, percent: status == "completed" ? 100.0 : 0.0 }
  end

  def progress_from_file
    match = File.read(progress_file_path).strip.match(/\A(\d+)\s+(\d+)\z/)
    return unless match

    done, total = match[1].to_i, match[2].to_i
    { completed: done, total: total, percent: total.positive? ? (done * 100.0 / total).round(1) : 0.0 }
  rescue SystemCallError
    nil
  end
end
