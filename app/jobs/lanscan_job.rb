# Runs a lanscan in the background and keeps its LanscanRun row up to date so
# the page can show a live progress bar and the final elapsed time. The Go
# binary now only reports JSON; this job is what persists the per-host rows.
class LanscanJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = LanscanRun.find(run_id)

    unless run.lan
      run.fail!("nessuna LAN associata alla scansione")
      return
    end

    run.start!(total_probes: LanscanRunner.probe_count(target: run.target, ports: run.ports))

    result = LanscanRunner.call(lan: run.lan, run:)

    if result.success
      persist(run, result.hosts)
      run.complete!(hosts_found: run.lanscans.where.not(open_ports: nil).count)
    else
      run.fail!(result.output)
    end
  rescue LanscanRunner::InvalidParams => e
    run&.fail!(e.message)
  ensure
    run&.cleanup_progress_file
  end

  private

  # One Lanscan row per reported host (open ports and/or a MAC address). Host
  # entries without a well-formed IP are dropped rather than aborting the whole
  # batch (LanscanResult already sanitises MAC and ports).
  def persist(run, hosts)
    scanned_at = run.started_at || Time.current
    valid = hosts.select { |host| host[:ip].to_s.match?(Lanscan::IP_FORMAT) }

    if valid.size < hosts.size
      Rails.logger.warn("[lanscan] run=#{run.id}: scartati #{hosts.size - valid.size} host con IP non valido")
    end

    LanscanRun.transaction do
      valid.each do |host|
        run.lanscans.create!(
          scanned_at: scanned_at,
          target: run.target,
          ip_address: host[:ip],
          mac_address: host[:mac],
          open_ports: host[:open_ports].join(" ").presence
        )
      end
    end
  end
end
