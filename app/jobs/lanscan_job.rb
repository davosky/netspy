# Runs a lanscan in the background: the scan of a whole subnet takes well over
# the 200ms threshold that belongs off the request cycle. Rows are persisted by
# the Go binary itself (see LanscanRunner).
class LanscanJob < ApplicationJob
  queue_as :default

  def perform(target: nil, ports: nil, timeout: nil)
    result = LanscanRunner.call(target:, ports:, timeout:)
    raise "lanscan terminato con errore" unless result.success
  end
end
