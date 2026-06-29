# frozen_string_literal: true

# Members may create/work creatives; mutations otherwise manager-gated.
class CreativePolicy < ApplicationPolicy
  def create? = member?

  def generate? = member?
end
