# One row per host found with open ports during a lanscan run. All rows of the
# same run share `scanned_at` and `target`; the rows are written by the Go
# `vendor/lanscan` binary (see LanscanRunner) or, in tests, by ActiveRecord.
class Lanscan < ApplicationRecord
  belongs_to :lanscan_run, optional: true

  scope :recent, -> { order(scanned_at: :desc, ip_address: :asc) }
  scope :for_run, ->(scanned_at) { where(scanned_at: scanned_at) }

  validates :scanned_at, presence: true
  validates :target, presence: true
  validates :ip_address, presence: true

  # Ports are stored space-separated ("22 80 443"), matching the Go binary.
  def open_ports_list
    open_ports.to_s.split.map(&:to_i)
  end
end
