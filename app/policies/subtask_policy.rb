# frozen_string_literal: true

class SubtaskPolicy < ApplicationPolicy
  def create?  = member?
  def update?  = member?
  def destroy? = member?
end
