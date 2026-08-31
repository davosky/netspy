require "open3"
require "ipaddr"

# Runs a lanscan for a Lan.
#
#   * primary Lan   -> exec the committed Go `vendor/lanscan` binary locally.
#   * secondary Lan -> exec that binary on the LAN's dedicated client over SSH
#                      (key auth only), so the remote ARP table is visible.
#
# Either way the binary emits a JSON report on stdout; NetSpy (LanscanJob) is
# what writes the rows. Every parameter is validated before a process starts and
# is passed as an argv array, never a shell string.
class LanscanRunner
  DEFAULT_PORTS      = "1-1024"
  DEFAULT_TIMEOUT    = 600
  TIMEOUT_RANGE      = (50..10_000)
  PORTS_FORMAT       = /\A(\d{1,5})-(\d{1,5})\z/
  REMOTE_USER_FORMAT = /\A[a-z_][a-z0-9_-]{0,31}\z/
  # `binpath` ends up as the command in `ssh <user>@<host> <binpath> …`, which
  # the remote login shell parses: allow only a plain path token (no spaces, no
  # shell metacharacters) so it can never carry an injected command.
  BINPATH_FORMAT     = %r{\A[\w@%+=:,./-]+\z}

  # Upper bound on the number of addresses a single scan may enumerate. Keeps a
  # scan bounded in time and resources; a target larger than a /20 is well
  # beyond a single LAN segment.
  MAX_HOSTS = 4096

  # Local fallback binary (committed) when a primary Lan leaves `binpath` blank.
  BIN_PATH = ENV.fetch("LANSCAN_BIN", Rails.root.join("vendor/lanscan/bin/lanscan").to_s)
  # Remote fallback command when a secondary Lan leaves `binpath` blank; assumed
  # to be on the client's PATH.
  REMOTE_BIN = ENV.fetch("LANSCAN_REMOTE_BIN", "lanscan")

  # Both optional. Leave them unset to rely on the invoking user's own SSH setup
  # (`~/.ssh/config`, default identity or agent, `~/.ssh/known_hosts`) — i.e.
  # whatever already makes `ssh <remote_user>@<remote_client_ip>` work by hand.
  # Set them only to pin a dedicated key / known_hosts file.
  SSH_KEY             = ENV["LANSCAN_SSH_KEY"]
  SSH_KNOWN_HOSTS     = ENV["LANSCAN_KNOWN_HOSTS"]
  SSH_CONNECT_TIMEOUT = 10

  LOG_DIR = Rails.root.join("log/lanscan")

  Result = Data.define(:success, :hosts, :output)

  class InvalidParams < StandardError; end

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

  # Raises InvalidParams unless `cidr` is an IPv4 network no wider than MAX_HOSTS.
  # Shared with the Lan model so both apply the same rule.
  def self.validate_cidr!(cidr)
    ip, prefix = cidr.to_s.split("/", 2)
    raise InvalidParams, "manca la maschera CIDR (es. 192.168.1.0/24)" if prefix.nil?
    raise InvalidParams, "non è un indirizzo IPv4" unless IPAddr.new(ip).ipv4?

    prefix = Integer(prefix, 10, exception: false)
    raise InvalidParams, "prefisso CIDR non valido (0-32)" unless prefix&.between?(0, 32)

    hosts = 2**(32 - prefix)
    raise InvalidParams, "subnet troppo ampia: #{hosts} indirizzi (max #{MAX_HOSTS})" if hosts > MAX_HOSTS
  rescue IPAddr::Error
    raise InvalidParams, "CIDR non valido: #{cidr}"
  end

  # Raises InvalidParams unless `ports` is "FROM-TO" within 1..65535. Shared.
  def self.validate_ports!(ports)
    match = PORTS_FORMAT.match(ports.to_s)
    raise InvalidParams, "intervallo porte non valido (es. 1-1024)" unless match

    from = match[1].to_i
    to = match[2].to_i
    raise InvalidParams, "intervallo porte fuori da 1-65535" unless from >= 1 && to <= 65_535 && from <= to
  end

  def initialize(lan:, run: nil)
    @lan = lan
    @run = run
  end

  def call
    validate!
    FileUtils.mkdir_p(LOG_DIR)

    output, status = @lan.remote? ? run_remote : run_local
    Rails.logger.info("[lanscan] lan=#{@lan.lan} remote=#{@lan.remote?} exit=#{status&.exitstatus}")

    unless status&.success?
      return Result.new(success: false, hosts: [], output: LanscanResult.error_message(output) || output.to_s)
    end

    Result.new(success: true, hosts: LanscanResult.parse(output).hosts, output: output)
  rescue LanscanResult::MalformedOutput => e
    Result.new(success: false, hosts: [], output: e.message)
  end

  # Raises LanscanRunner::InvalidParams on any bad parameter. Called on its own
  # by the controller (fail fast before enqueuing) and again inside #call.
  def validate!
    raise InvalidParams, "nessuna LAN associata alla scansione" if @lan.nil?

    self.class.validate_cidr!(@lan.lan)
    self.class.validate_ports!(@lan.ports)
    raise InvalidParams, "timeout non valido (#{TIMEOUT_RANGE})" unless TIMEOUT_RANGE.cover?(@lan.timeout.to_i)
    if @lan.binpath.present? && !@lan.binpath.match?(BINPATH_FORMAT)
      raise InvalidParams, "percorso eseguibile lanscan non valido"
    end

    @lan.remote? ? validate_remote! : validate_local!
  end

  private

  def validate_local!
    raise InvalidParams, "eseguibile lanscan non trovato: #{local_bin}" unless File.executable?(local_bin)
  end

  def validate_remote!
    raise InvalidParams, "indirizzo client remoto non IPv4" unless ipv4?(@lan.remote_client_ip)
    raise InvalidParams, "utente remoto non valido" unless @lan.remote_user.to_s.match?(REMOTE_USER_FORMAT)
    raise InvalidParams, "chiave SSH non leggibile: #{SSH_KEY}" if SSH_KEY.present? && !File.readable?(SSH_KEY.to_s)
  end

  # Local scan: capture stdout (the JSON report) on its own; the binary writes
  # the progress file itself via -progress-file.
  def run_local
    stdout, stderr, status = Open3.capture3(local_bin, *cli_args(progress: true), chdir: Rails.root.to_s)
    [ stdout.presence || stderr, status ]
  end

  # Remote scan: stdout carries the JSON report; stderr carries `PROGRESS done
  # total` lines, which we mirror into the run's progress file so the existing
  # progress bar works for remote scans too. Any other stderr is error text.
  def run_remote
    stdout = +""
    stderr_tail = +""
    status = nil

    Open3.popen3(*ssh_argv) do |stdin, out, err, wait_thr|
      stdin.close
      pump = Thread.new do
        err.each_line do |line|
          if (match = line.match(/\APROGRESS (\d+) (\d+)\s*\z/))
            write_progress_file(match[1].to_i, match[2].to_i)
          else
            stderr_tail << line
          end
        end
      end
      stdout = out.read
      pump.join
      status = wait_thr.value
    end

    [ stdout.presence || stderr_tail, status ]
  end

  def cli_args(progress:)
    args = [
      "-target", @lan.lan,
      "-ports", @lan.ports,
      "-timeout", @lan.timeout.to_s,
      "-format", "json"
    ]
    args += [ "-progress-file", @run.progress_file_path.to_s ] if progress && @run
    args
  end

  # Plain `ssh user@host lanscan …`, deferring to the invoking user's SSH config
  # (the setup that already works by hand). `-i` / `UserKnownHostsFile` are added
  # only when explicitly pinned via ENV. `BatchMode=yes` keeps a background job
  # from hanging on a prompt — it fails fast instead.
  def ssh_argv
    argv = [ "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=#{SSH_CONNECT_TIMEOUT}" ]
    argv += [ "-i", SSH_KEY, "-o", "IdentitiesOnly=yes" ] if SSH_KEY.present?
    argv += [ "-o", "UserKnownHostsFile=#{SSH_KNOWN_HOSTS}" ] if SSH_KNOWN_HOSTS.present?
    argv += [ "#{@lan.remote_user}@#{@lan.remote_client_ip}", remote_bin, *cli_args(progress: false) ]
    argv
  end

  def local_bin
    @lan.binpath.presence || BIN_PATH
  end

  def remote_bin
    @lan.binpath.presence || REMOTE_BIN
  end

  # Atomic (temp + rename) so LanscanRun#live_progress never reads a partial line.
  def write_progress_file(done, total)
    return unless @run

    path = @run.progress_file_path
    tmp = "#{path}.tmp"
    File.write(tmp, "#{done} #{total}\n")
    File.rename(tmp, path)
  rescue SystemCallError
    nil
  end

  def ipv4?(value)
    IPAddr.new(value.to_s).ipv4?
  rescue IPAddr::Error
    false
  end
end
