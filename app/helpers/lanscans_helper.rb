module LanscansHelper
  # "m:ss" — same shape as the JS progress controller's formatDuration.
  def human_duration(seconds)
    total = seconds.to_f.round
    format("%d:%02d", total / 60, total % 60)
  end
end
