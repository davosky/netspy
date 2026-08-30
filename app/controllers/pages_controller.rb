class PagesController < ApplicationController
  before_action :authenticate_user!

  def index
    @lanscan_defaults = LanscanRunner.defaults
  end

  def credits; end
end
