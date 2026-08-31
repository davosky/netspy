module LanscansHelper
  # "m:ss" — same shape as the JS progress controller's formatDuration.
  def human_duration(seconds)
    total = seconds.to_f.round
    format("%d:%02d", total / 60, total % 60)
  end

  # Label for a LAN in the launch <select>: the subnet plus where it is scanned
  # from (locally for the primary LAN, or the remote client for a secondary one).
  def lan_option_label(lan)
    where = lan.primary? ? t("lanscans.form.local") : "→ #{lan.remote_client_ip}"
    "#{lan.lan}  ·  #{where}"
  end

  # Heading for a result card: prefer the LAN, fall back to the run's target.
  def lanscan_group_title(run, rows)
    run&.lan&.lan || run&.target || rows.first.target
  end

  # IP of the machine that ran the scan, so the results table can flag its row.
  # For a secondary LAN that's the dedicated remote client; a primary LAN is
  # scanned by the server itself and has no distinct client address.
  def lanscan_scanner_ip(run)
    run.lan.remote_client_ip if run&.lan&.secondary?
  end
end
