# frozen_string_literal: true

# Base policy. An admin user may do anything; everyone else is denied by
# default and specific policies opt individual actions back in.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index? = admin?
  def show? = admin?
  def create? = admin?
  def new? = create?
  def update? = admin?
  def edit? = update?
  def destroy? = admin?

  def admin?
    user&.admin?
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      user&.admin? ? scope.all : scope.none
    end

    private

    attr_reader :user, :scope
  end
end
