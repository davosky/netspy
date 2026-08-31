# frozen_string_literal: true

# Configured LANs are readable by any authenticated user (they pick one to scan
# on the lanscans page). Creating and editing them — remote client IPs, SSH
# users, binary paths — is an admin task and happens through Administrate, so
# ApplicationPolicy's admin-only defaults for the write actions are left as-is.
class LanPolicy < ApplicationPolicy
  def index? = user.present?
  def show? = user.present?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
