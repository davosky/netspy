module Admin
  class UsersController < Admin::ApplicationController
    # See https://administrate-demo.herokuapp.com/customizing_controller_actions
    # for more information on customizing this controller.

    private

    # Drop a blank password on edit so Devise keeps the current one.
    def resource_params
      permitted = params.require(:user).permit(dashboard.permitted_attributes(action_name))
      permitted.delete(:password) if permitted[:password].blank?
      permitted
    end
  end
end
