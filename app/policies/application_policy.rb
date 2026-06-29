# frozen_string_literal: true

# Base Pundit policy keyed on the active membership role + workspace isolation.
class ApplicationPolicy
  attr_reader :membership, :record

  def initialize(membership, record)
    @membership = membership
    @record = record
  end

  def index?   = membership.present?
  def show?    = same_workspace?
  def create?  = manager?
  def update?  = manager?
  def destroy? = manager?

  protected

  def manager? = membership&.can_manage?
  def admin?   = membership&.can_admin?
  def owner?   = membership&.owner?
  def member?  = membership.present? && !membership.guest?

  # Enforces tenant isolation: the record must belong to the active workspace.
  def same_workspace?
    return false unless membership

    rec_ws = record.respond_to?(:workspace_id) ? record.workspace_id : nil
    rec_ws.nil? || rec_ws == membership.workspace_id
  end

  class Scope
    attr_reader :membership, :scope

    def initialize(membership, scope)
      @membership = membership
      @scope = scope
    end

    def resolve
      scope.where(workspace_id: membership.workspace_id)
    end
  end
end
