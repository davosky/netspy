require "open3"

namespace :lanscan do
  desc "Package the lanscan client binary + install notes into tmp/lanscan-client.tar.gz"
  task :package do
    bin = Rails.root.join("vendor/lanscan/bin/lanscan")
    abort "eseguibile non trovato: #{bin} (esegui bin/build-lanscan)" unless File.executable?(bin)

    staging = Rails.root.join("tmp/lanscan-client")
    FileUtils.rm_rf(staging)
    FileUtils.mkdir_p(staging)
    FileUtils.cp(bin, staging.join("lanscan"))
    File.write(staging.join("INSTALL.md"), <<~MD)
      # lanscan — client per LAN secondaria NetSpy

      1. Copia `lanscan` sul client (es. `/usr/local/bin/lanscan`) e `chmod +x`.
         Se lo metti altrove, indica il percorso nel campo `binpath` della LAN.
      2. Autorizza la chiave pubblica SSH del server NetSpy per l'utente indicato
         in `remote_user`:
             mkdir -p ~/.ssh && chmod 700 ~/.ssh
             echo '<contenuto di LANSCAN_SSH_KEY.pub>' >> ~/.ssh/authorized_keys
             chmod 600 ~/.ssh/authorized_keys
      3. Requisiti: Linux con `/proc/net/arp` (per i MAC address) e raggiungibilità
         TCP verso la subnet da scansionare. Nessun database, nessun altro runtime.

      Il server esegue: `ssh <remote_user>@<remote_client_ip> lanscan -target <cidr>
      -ports <range> -timeout <ms> -format json`.
    MD

    tarball = Rails.root.join("tmp/lanscan-client.tar.gz")
    system("tar", "-czf", tarball.to_s, "-C", staging.dirname.to_s, "lanscan-client", exception: true)
    puts "creato #{tarball}"
  end

  desc "Copy the lanscan binary onto a secondary LAN's client over SSH: rake 'lanscan:deploy[LAN_ID]'"
  task :deploy, [ :lan_id ] => :environment do |_t, args|
    lan = Lan.find(args.fetch(:lan_id))
    abort "la LAN #{lan.lan} non è secondaria" unless lan.secondary?

    bin = Rails.root.join("vendor/lanscan/bin/lanscan")
    dest = lan.binpath.presence || "lanscan"

    # Same policy as LanscanRunner: rely on the user's SSH config unless a key /
    # known_hosts file is explicitly pinned via ENV.
    ssh_opts = [ "-o", "BatchMode=yes" ]
    ssh_opts += [ "-i", ENV["LANSCAN_SSH_KEY"], "-o", "IdentitiesOnly=yes" ] if ENV["LANSCAN_SSH_KEY"].present?
    ssh_opts += [ "-o", "UserKnownHostsFile=#{ENV['LANSCAN_KNOWN_HOSTS']}" ] if ENV["LANSCAN_KNOWN_HOSTS"].present?
    target = "#{lan.remote_user}@#{lan.remote_client_ip}"

    system("scp", *ssh_opts, bin.to_s, "#{target}:#{dest}", exception: true)
    system("ssh", *ssh_opts, target, "chmod", "+x", dest, exception: true)
    puts "lanscan installato su #{target}:#{dest}"
  end
end
