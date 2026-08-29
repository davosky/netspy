class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :configure_permitted_parameters, if: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  layout :layout_by_resource

  private

  # Devise pages (sign in, password reset, ...) use the bare, centered layout;
  # everything else gets the full chrome with the navbar.
  def layout_by_resource
    devise_controller? ? "authentication" : "application"
  end

  def configure_permitted_parameters
    extra = %i[username first_name last_name gender region province category]
    devise_parameter_sanitizer.permit(:sign_up, keys: extra)
    devise_parameter_sanitizer.permit(:account_update, keys: extra)
  end

  def user_not_authorized
    flash[:alert] = t("pundit.not_authorized")
    redirect_back fallback_location: root_path
  end
end
