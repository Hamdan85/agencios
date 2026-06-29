# frozen_string_literal: true

# Managers+ manage clients; members read; guests may only read.
class ClientPolicy < ApplicationPolicy
  def index?   = membership.present?
  def show?    = same_workspace?
  def create?  = manager?
  def update?  = manager?
  def destroy? = manager?
  def archive? = manager?
end
