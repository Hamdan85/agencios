# frozen_string_literal: true

class TicketPolicy < ApplicationPolicy
  def create?  = member?
  def update?  = member?
  def advance? = member?
  def destroy? = manager?

  class Scope < ApplicationPolicy::Scope
  end
end
