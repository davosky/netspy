# frozen_string_literal: true

# Progress of a scan is visible to any authenticated user, like the results.
class LanscanRunPolicy < ApplicationPolicy
  def show? = user.present?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
