# Runs a lanscan in the background and keeps its LanscanRun row up to date so
# the page can show a live progress bar and the final elapsed time. Per-host
# rows are persisted by the Go binary itself (see LanscanRunner).
class LanscanJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = LanscanRun.find(run_id)
    run.start!(total_probes: LanscanRunner.probe_count(target: run.target, ports: run.ports))

    result = LanscanRunner.call(target: run.target, ports: run.ports, timeout: run.timeout, run:)

    if result.success
      run.complete!(hosts_found: run.lanscans.count)
    else
      run.fail!(result.output)
    end
  rescue LanscanRunner::InvalidParams => e
    run&.fail!(e.message)
  ensure
    run&.cleanup_progress_file
  end
end
