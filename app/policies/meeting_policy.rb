# frozen_string_literal: true

# Managers+ manage meetings; members read; guests may only read.
class MeetingPolicy < ApplicationPolicy
  def index?   = membership.present?
  def show?    = same_workspace?
  def create?  = manager?
  def update?  = manager?
  def destroy? = manager?
end
