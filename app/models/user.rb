# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password validations: false

  has_many :memberships, dependent: :destroy
  has_many :workspaces, through: :memberships
  has_many :sessions, dependent: :destroy
  has_many :assigned_tickets, class_name: "Ticket", foreign_key: :assignee_id, dependent: :nullify, inverse_of: :assignee
  has_many :created_tickets, class_name: "Ticket", foreign_key: :created_by_id, dependent: :nullify, inverse_of: :created_by
  has_many :assigned_subtasks, class_name: "Subtask", foreign_key: :assignee_id, dependent: :nullify, inverse_of: :assignee
  has_many :generations, dependent: :nullify
  has_many :push_subscriptions, dependent: :destroy

  has_one_attached :avatar

  encrypts :google_access_token, :google_refresh_token

  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false }

  generates_token_for :password_reset, expires_in: 20.minutes do
    password_salt&.last(10)
  end
  generates_token_for :email_confirmation, expires_in: 24.hours
  generates_token_for :email_change, expires_in: 24.hours

  # ── Tenancy resolution ───────────────────────────────────────────
  def default_workspace
    memberships.order(:created_at).first&.workspace
  end

  def membership_for(workspace)
    return nil unless workspace
    memberships.find_by(workspace_id: workspace.id)
  end

  def role_in(workspace)
    membership_for(workspace)&.role
  end

  def member_of?(workspace)
    return false unless workspace
    memberships.exists?(workspace_id: workspace.id)
  end

  def can_manage?(workspace)
    membership_for(workspace)&.can_manage? || false
  end

  def owner_of?(workspace) = membership_for(workspace)&.owner? || false
  def admin_of?(workspace) = membership_for(workspace)&.can_admin? || false

  # Workspaces this user created (i.e. owns). The owned count is what the
  # per-user creation limit is measured against — being invited into other
  # workspaces as a non-owner does not consume the quota.
  def owned_workspaces_count = memberships.owner.count

  # Whether the user may create another workspace, per the configurable
  # per-user limit (see SystemConfig.max_workspaces_per_user).
  def can_create_workspace? = owned_workspaces_count < SystemConfig.max_workspaces_per_user

  # ── Display / integration state ──────────────────────────────────
  def display_name
    name.presence || email.to_s.split("@").first
  end

  def staff? = staff
  def google_connected? = google_uid.present?
  def google_calendar_connected? = google_calendar_connected_at.present?
  def email_confirmed? = confirmed_at.present?

  # ── Claude connector (tokenized MCP URL) ─────────────────────────
  # A long-lived secret embedded in the user's MCP connector URL. This is the
  # bearer credential for the tokenized /mcp/c/:token endpoint (no OAuth), so the
  # user can paste one URL into Claude. Generated on first use, rotatable.
  def mcp_connector_token!
    mcp_connector_token.presence || rotate_mcp_connector_token!
  end

  def rotate_mcp_connector_token!
    update!(mcp_connector_token: "agc_#{SecureRandom.urlsafe_base64(32)}")
    mcp_connector_token
  end

  # Feeds the My Tasks (`/tarefas`) screen across all workspaces.
  def assigned_open_subtasks
    Subtask.where(assignee_id: id, done: false)
  end

  def billing_active?(workspace)
    workspace&.subscription&.access_granted? || false
  end

  # ── ActiveAdmin (LGPD: never expose secrets) ─────────────────────────
  # Deliberately omits password_digest and every encrypted/token column so they
  # can't be searched or surfaced in the admin panel.
  def self.ransackable_attributes(_auth = nil)
    %w[id email name staff confirmed_at created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil)
    %w[memberships workspaces]
  end
end
