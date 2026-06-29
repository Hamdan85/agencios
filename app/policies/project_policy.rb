# frozen_string_literal: true

# Managers+ manage projects; members read; guests may only read.
class ProjectPolicy < ApplicationPolicy
  def index?   = membership.present?
  def show?    = same_workspace?
  def create?  = manager?
  def update?  = manager?
  def destroy? = manager?
end
