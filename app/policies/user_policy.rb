# frozen_string_literal: true

# Admins manage every user (rules inherited from ApplicationPolicy).
# A non-admin may only view and edit their own record.
class UserPolicy < ApplicationPolicy
  def show? = admin? || owner?
  def update? = admin? || owner?
  def destroy? = admin?

  private

  def owner?
    user.present? && user == record
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user&.admin?
      return scope.where(id: user.id) if user

      scope.none
    end
  end
end
