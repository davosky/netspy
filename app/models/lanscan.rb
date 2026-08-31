require "resolv"

# One row per host found during a lanscan run (open ports and/or a MAC address).
# All rows of the same run share `scanned_at` and `target`; the rows are written
# by LanscanJob from the Go `vendor/lanscan` report, or in tests by ActiveRecord.
class Lanscan < ApplicationRecord
  belongs_to :lanscan_run, optional: true

  # `ip_address` is a string column: cast to PostgreSQL `inet` so hosts sort
  # numerically (…1.2, …1.10, …1.100) rather than lexically (…1.10, …1.100, …1.2).
  # The IP-format validation below is what keeps that cast from ever failing.
  BY_IP = Arel.sql("ip_address::inet ASC")

  IP_FORMAT  = Regexp.union(Resolv::IPv4::Regex, Resolv::IPv6::Regex)
  MAC_FORMAT = /\A[0-9a-f]{2}(:[0-9a-f]{2}){5}\z/i

  scope :recent, -> { order(scanned_at: :desc).order(BY_IP) }
  scope :for_run, ->(scanned_at) { where(scanned_at: scanned_at) }

  validates :scanned_at, presence: true
  validates :target, presence: true
  validates :ip_address, presence: true, format: { with: IP_FORMAT }
  validates :mac_address, format: { with: MAC_FORMAT }, allow_blank: true

  # Ports are stored space-separated ("22 80 443"), matching the Go binary.
  def open_ports_list
    open_ports.to_s.split.map(&:to_i)
  end
end
