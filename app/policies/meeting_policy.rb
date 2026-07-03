# frozen_string_literal: true

# Meetings are personal: any non-guest member schedules their own; only the
# OWNER (the user who scheduled it) may edit or delete it. Everyone in the
# workspace can read — the client page lists every meeting of a client.
class MeetingPolicy < ApplicationPolicy
  def index?   = membership.present?
  def show?    = same_workspace?
  def create?  = member?
  def update?  = owner_of_meeting?
  def destroy? = owner_of_meeting?

  private

  def owner_of_meeting?
    same_workspace? && record.respond_to?(:user_id) && record.user_id == membership.user_id
  end
end
