class LanscanRunsController < ApplicationController
  before_action :authenticate_user!

  # JSON progress snapshot polled by the progress bar on the lanscans page.
  def show
    lanscan_run = LanscanRun.find(params[:id])
    authorize lanscan_run
    progress = lanscan_run.live_progress

    render json: {
      status: lanscan_run.status,
      percent: progress[:percent],
      completed: progress[:completed],
      total: progress[:total],
      elapsed: lanscan_run.elapsed_seconds,
      hosts_found: lanscan_run.hosts_found,
      error: lanscan_run.error_message
    }
  end
end
