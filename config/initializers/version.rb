# Application version, parsed from the VERSION file at the repo root so there is
# a single source of truth (the same file is read by humans and CI).
module NetSpy
  module Version
    values = Rails.root.join("VERSION").read.each_line.filter_map do |line|
      key, value = line.split(":", 2)
      [ key.strip, value.strip ] if value
    end.to_h

    NUMBER   = values.fetch("version")
    CODENAME = values.fetch("codename")
    DATE     = values["date"]
    STRING   = "#{NUMBER} (#{CODENAME})".freeze

    def self.to_s = STRING
  end
end
