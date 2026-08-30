require "open3"
require "ipaddr"

# Runs the compiled Go `vendor/lanscan` binary, passing it the NetSpy database
# connection through the environment so it writes straight into the `lanscans`
# table. All user-supplied parameters are validated before the process starts
# and are passed as an argv array (never a shell string).
class LanscanRunner
  DEFAULT_TARGET  = "10.182.1.0/24"
  DEFAULT_PORTS   = "1-1024"
  DEFAULT_TIMEOUT = 550
  TIMEOUT_RANGE   = (50..10_000)

  # Upper bound on the number of addresses a single scan may enumerate. Keeps a
  # scan bounded in time and resources; a target larger than a /20 is well
  # beyond a single LAN segment. Raise only if a deployment genuinely needs it.
  MAX_HOSTS = 4096

  BIN_PATH = ENV.fetch("LANSCAN_BIN", Rails.root.join("vendor/lanscan/bin/lanscan").to_s)
  LOG_DIR  = Rails.root.join("log/lanscan")

  Result = Data.define(:success, :output)

  class InvalidParams < StandardError; end

  def self.defaults
    { target: DEFAULT_TARGET, ports: DEFAULT_PORTS, timeout: DEFAULT_TIMEOUT }
  end

  def self.call(...) = new(...).call

  # Number of TCP probes a scan of `target` over `ports` will perform
  # (hosts * ports) — used to pre-fill a run's progress total.
  def self.probe_count(target:, ports:)
    _ip, prefix = target.to_s.split("/", 2)
    hosts = 2**(32 - prefix.to_i)
    from, to = ports.to_s.split("-", 2).map(&:to_i)
    hosts * (to - from + 1)
  rescue StandardError
    0
  end

  def initialize(target: nil, ports: nil, timeout: nil, run: nil)
    @target  = target.presence || DEFAULT_TARGET
    @ports   = ports.presence || DEFAULT_PORTS
    @timeout = Integer(timeout.presence || DEFAULT_TIMEOUT, exception: false)
    @run     = run
  end

  # Normalised parameters (defaults applied), for persisting a LanscanRun.
  def to_params
    { target: @target, ports: @ports, timeout: @timeout }
  end

  def call
    validate!
    FileUtils.mkdir_p(LOG_DIR)
    output, status = Open3.capture2e(db_env, BIN_PATH, *cli_args, chdir: Rails.root.to_s)
    Rails.logger.info("[lanscan] target=#{@target} exit=#{status.exitstatus}\n#{output}")
    Result.new(success: status.success?, output:)
  end

  # Raises LanscanRunner::InvalidParams on any bad parameter. Called on its own
  # by the controller (fail fast before enqueuing) and again inside #call.
  def validate!
    raise InvalidParams, "eseguibile lanscan non trovato: #{BIN_PATH}" unless File.executable?(BIN_PATH)
    validate_target!
    validate_ports!
    raise InvalidParams, "timeout non valido (#{TIMEOUT_RANGE})" unless @timeout && TIMEOUT_RANGE.cover?(@timeout)
  end

  private

  def validate_target!
    ip, prefix = @target.split("/", 2)
    raise InvalidParams, "target senza maschera CIDR (es. 192.168.1.0/24)" if prefix.nil?
    raise InvalidParams, "target non IPv4" unless IPAddr.new(ip).ipv4?

    prefix = Integer(prefix, 10, exception: false)
    raise InvalidParams, "prefisso CIDR non valido (0-32)" unless prefix&.between?(0, 32)

    hosts = 2**(32 - prefix)
    raise InvalidParams, "subnet troppo ampia: #{hosts} indirizzi (max #{MAX_HOSTS})" if hosts > MAX_HOSTS
  rescue IPAddr::Error
    raise InvalidParams, "target CIDR non valido: #{@target}"
  end

  def validate_ports!
    match = /\A(\d{1,5})-(\d{1,5})\z/.match(@ports)
    raise InvalidParams, "range porte non valido (es. 1-1024)" unless match

    from, to = match[1].to_i, match[2].to_i
    raise InvalidParams, "range porte fuori da 1-65535" unless from >= 1 && to <= 65_535 && from <= to
  end

  def cli_args
    args = [
      "-target", @target,
      "-ports", @ports,
      "-timeout", @timeout.to_s,
      "-table", Lanscan.table_name,
      "-log-dir", LOG_DIR.to_s
    ]
    if @run
      args += [ "-run-id", @run.id.to_s, "-progress-file", @run.progress_file_path.to_s ]
    end
    args
  end

  # libpq-style variables consumed directly by lib/pq inside the Go binary.
  def db_env
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    {
      "PGHOST"     => config[:host].to_s,
      "PGPORT"     => config[:port].to_s.presence || "5432",
      "PGDATABASE" => config[:database].to_s,
      "PGUSER"     => config[:username].to_s.presence || ENV["USER"].to_s,
      "PGPASSWORD" => config[:password].to_s,
      "PGSSLMODE"  => "prefer",
      "PGCONNECT_TIMEOUT" => "5"
    }
  end
end
