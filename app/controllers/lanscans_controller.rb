class LanscansController < ApplicationController
  before_action :authenticate_user!

  # Launch form (+ live progress of a running scan) plus the results grouped by
  # run (same scanned_at), newest first.
  def index
    authorize Lanscan
    @lanscan_defaults = LanscanRunner.defaults
    @active_run = LanscanRun.find_by(id: params[:run]) || LanscanRun.in_progress.recent.first
    @runs = policy_scope(Lanscan).recent.group_by(&:scanned_at)
  end

  def show
    @lanscan = policy_scope(Lanscan).find(params[:id])
    authorize @lanscan
  end

  # Validates the parameters, records a LanscanRun and enqueues the background
  # scan; the page then polls the run for progress.
  def run
    authorize Lanscan, :run?
    options = params.permit(:target, :ports, :timeout).to_h.symbolize_keys
    runner = LanscanRunner.new(**options)
    runner.validate!
    lanscan_run = LanscanRun.create!(status: "pending", user: current_user, **runner.to_params)
    LanscanJob.perform_later(lanscan_run.id)
    redirect_to lanscans_path(run: lanscan_run.id), notice: t("lanscans.run.enqueued", target: lanscan_run.target)
  rescue LanscanRunner::InvalidParams => e
    redirect_to lanscans_path, alert: e.message
  end
end
