class LanscansController < ApplicationController
  before_action :authenticate_user!

  # Launch form (pick a configured LAN) + live progress of a running scan, plus
  # the results grouped by run, newest first.
  def index
    authorize Lanscan
    @lans = policy_scope(Lan).ordered
    @active_run = LanscanRun.find_by(id: params[:run]) || LanscanRun.in_progress.recent.first
    # Only the most recent scan's results are shown (rows are ordered newest
    # first, so the first group is the last scan).
    @last_run, @last_rows = policy_scope(Lanscan).includes(lanscan_run: :lan).recent.group_by(&:lanscan_run).first
  end

  def show
    @lanscan = policy_scope(Lanscan).find(params[:id])
    authorize @lanscan
  end

  # Records a LanscanRun for the chosen LAN and enqueues the background scan;
  # the page then polls the run for progress. Parameters come from the Lan, not
  # from the form, so they are already validated — but re-check so a bad SSH
  # setup is reported here rather than only in the job.
  def run
    authorize Lanscan, :run?
    lan = Lan.find(params.require(:lan_id))
    LanscanRunner.new(lan: lan).validate!

    lanscan_run = LanscanRun.create!(
      status: "pending", user: current_user, lan: lan,
      target: lan.lan, ports: lan.ports, timeout: lan.timeout
    )
    LanscanJob.perform_later(lanscan_run.id)
    redirect_to lanscans_path(run: lanscan_run.id), notice: t("lanscans.run.enqueued", target: lan.lan)
  rescue ActiveRecord::RecordNotFound
    redirect_to lanscans_path, alert: t("lanscans.run.lan_not_found")
  rescue LanscanRunner::InvalidParams => e
    redirect_to lanscans_path, alert: e.message
  end
end
