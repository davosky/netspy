class LanscansController < ApplicationController
  before_action :authenticate_user!

  # Launch form plus the results grouped by run (same scanned_at), newest first.
  def index
    authorize Lanscan
    @lanscan_defaults = LanscanRunner.defaults
    @runs = policy_scope(Lanscan).recent.group_by(&:scanned_at)
  end

  def show
    @lanscan = policy_scope(Lanscan).find(params[:id])
    authorize @lanscan
  end

  # Enqueues a background scan with the parameters entered on the landing page.
  def run
    authorize Lanscan, :run?
    options = params.permit(:target, :ports, :timeout).to_h.symbolize_keys
    LanscanRunner.new(**options).validate!
    LanscanJob.perform_later(**options)
    redirect_to lanscans_path, notice: t("lanscans.run.enqueued", target: options[:target].presence || LanscanRunner::DEFAULT_TARGET)
  rescue LanscanRunner::InvalidParams => e
    redirect_to lanscans_path, alert: e.message
  end
end
