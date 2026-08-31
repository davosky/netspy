require "json"

# Parses the JSON report emitted by `vendor/lanscan -format json`. The Go binary
# no longer touches the database: it prints one JSON document on stdout and
# NetSpy (LanscanJob) is what persists the rows.
class LanscanResult
  class MalformedOutput < StandardError; end

  # The remote client that produces this JSON is trusted infrastructure, but a
  # compromised or buggy one must not be able to poison the database: sanitise
  # every field here so LanscanJob only ever persists well-formed values.
  MAC_FORMAT = /\A[0-9a-f]{2}(:[0-9a-f]{2}){5}\z/i

  Report = Data.define(:target, :ports, :started_at, :finished_at, :hosts_alive, :hosts)

  # Returns a Report. `hosts` is an array of
  # `{ ip:, mac: (nil unless a valid MAC), open_ports: [Integer in 1..65535] }`.
  # Raises MalformedOutput on unparseable output or an `{"error": ...}` payload.
  def self.parse(output)
    data = JSON.parse(output.to_s)
    raise MalformedOutput, "risposta non valida dallo scanner" unless data.is_a?(Hash)
    raise MalformedOutput, data["error"].to_s if data["error"].present?

    hosts = Array(data["hosts"]).map do |host|
      mac = host["mac"].to_s.strip
      {
        ip: host["ip"].to_s.strip,
        mac: (mac if mac.match?(MAC_FORMAT)),
        open_ports: Array(host["open_ports"]).map(&:to_i).select { |port| port.between?(1, 65_535) }.uniq
      }
    end

    Report.new(
      target: data["target"],
      ports: data["ports"],
      started_at: data["started_at"],
      finished_at: data["finished_at"],
      hosts_alive: data["hosts_alive"].to_i,
      hosts: hosts
    )
  rescue JSON::ParserError => e
    raise MalformedOutput, "output JSON non interpretabile: #{e.message}"
  end

  # If `output` is a `{"error": "..."}` payload, returns that message; else nil.
  def self.error_message(output)
    data = JSON.parse(output.to_s)
    data.is_a?(Hash) ? data["error"].presence : nil
  rescue JSON::ParserError
    nil
  end
end
