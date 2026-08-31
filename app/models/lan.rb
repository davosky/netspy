require "ipaddr"

# A network segment NetSpy can scan.
#
# The *primary* LAN is the one the web server sits on: it is scanned locally by
# running the committed Go `vendor/lanscan` binary. Each *secondary* LAN is
# scanned over SSH through a dedicated Linux client that runs its own copy of the
# same binary, so the ARP table — and therefore the MAC addresses — of that
# segment become visible. WAN / VLAN / WiFi segments are just secondary LANs
# whose client lives inside them.
class Lan < ApplicationRecord
  has_many :lanscan_runs, dependent: :nullify

  validates :lan, presence: true, uniqueness: { case_sensitive: false }
  validates :ports, presence: true
  validates :timeout, presence: true,
                      numericality: { only_integer: true, in: LanscanRunner::TIMEOUT_RANGE }
  validates :remote_user, format: { with: LanscanRunner::REMOTE_USER_FORMAT }, allow_blank: true
  # `binpath` becomes the command run over SSH on the client — keep it a plain
  # path token so it can never smuggle a shell command.
  validates :binpath, format: { with: LanscanRunner::BINPATH_FORMAT }, allow_blank: true

  validate :lan_within_cidr_limits
  validate :ports_within_range
  validate :exactly_one_role
  validate :remote_fields_consistent

  scope :primary_lan, -> { where(primary: true) }
  scope :secondary_lans, -> { where(secondary: true) }
  scope :ordered, -> { order(:lan) }

  # The scan runs locally on the server for the primary LAN, and over SSH on the
  # dedicated client for every secondary LAN.
  def local? = primary?
  def remote? = secondary?

  def to_s = lan.to_s

  private

  def lan_within_cidr_limits
    LanscanRunner.validate_cidr!(lan)
  rescue LanscanRunner::InvalidParams => e
    errors.add(:lan, e.message)
  end

  def ports_within_range
    LanscanRunner.validate_ports!(ports)
  rescue LanscanRunner::InvalidParams => e
    errors.add(:ports, e.message)
  end

  def exactly_one_role
    return if primary? ^ secondary?

    errors.add(:base, I18n.t("activerecord.errors.models.lan.one_role_required"))
  end

  def remote_fields_consistent
    if secondary?
      errors.add(:remote_client_ip, :blank) if remote_client_ip.blank?
      errors.add(:remote_user, :blank) if remote_user.blank?
      if remote_client_ip.present? && !ipv4?(remote_client_ip)
        errors.add(:remote_client_ip, I18n.t("activerecord.errors.models.lan.not_ipv4"))
      end
    else
      errors.add(:remote_client_ip, I18n.t("activerecord.errors.models.lan.primary_no_remote")) if remote_client_ip.present?
      errors.add(:remote_user, I18n.t("activerecord.errors.models.lan.primary_no_remote")) if remote_user.present?
    end
  end

  def ipv4?(value)
    IPAddr.new(value.to_s).ipv4?
  rescue IPAddr::Error
    false
  end
end
