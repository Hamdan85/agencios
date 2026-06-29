# frozen_string_literal: true

# Members may trigger generations; reads scoped to the workspace.
class GenerationPolicy < ApplicationPolicy
  def create? = member?
end
