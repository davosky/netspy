# frozen_string_literal: true

# Any authenticated user may view scan results and launch a scan: it is the
# core function of the tool. ApplicationPolicy already grants everything to
# admins; here we reopen the read actions and the custom `run` action to all
# signed-in users.
class LanscanPolicy < ApplicationPolicy
  def index? = user.present?
  def show? = user.present?
  def run? = user.present?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
