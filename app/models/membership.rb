# frozen_string_literal: true

class Membership < ApplicationRecord
  belongs_to :workspace
  belongs_to :user

  enum :role, { owner: 0, admin: 1, manager: 2, member: 3, guest: 4 }

  # Capability ranking — used for "role >= X" gating in policies.
  RANK = { "owner" => 4, "admin" => 3, "manager" => 2, "member" => 1, "guest" => 0 }.freeze

  validates :user_id, uniqueness: { scope: :workspace_id }
  validate  :single_owner_per_workspace

  def at_least?(other_role)
    RANK.fetch(role.to_s, -1) >= RANK.fetch(other_role.to_s, 999)
  end

  def can_manage? = at_least?(:manager)
  def can_admin?  = at_least?(:admin)

  private

  def single_owner_per_workspace
    return unless owner?

    clash = Membership.where(workspace_id: workspace_id, role: :owner).where.not(id: id)
    errors.add(:role, "workspace already has an owner") if clash.exists?
  end
end
