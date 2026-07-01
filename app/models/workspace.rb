# frozen_string_literal: true

# The tenant root — an agency. Everything domain-level hangs off a workspace.
class Workspace < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :clients, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :tickets, dependent: :destroy
  has_many :meetings, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :social_accounts, dependent: :destroy
  has_many :creatives, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :generations, dependent: :destroy
  has_many :strategy_sessions, dependent: :destroy
  has_one  :setting, dependent: :destroy
  has_one  :subscription, dependent: :destroy
  has_one  :credit_wallet, dependent: :destroy
  has_many :credit_transactions, dependent: :destroy

  has_one_attached :logo
  has_one_attached :default_creator_avatar

  SLUG_FORMAT = /\A[a-z0-9][a-z0-9-]{0,61}[a-z0-9]?\z/

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: SLUG_FORMAT }

  def seat_count = memberships.count
  def plan = subscription&.plan&.to_sym || :solo
  def trialing? = subscription&.trialing? || false

  # The billing gate. Godfathered (founding) workspaces bypass it entirely and
  # always have access. Otherwise access follows the subscription.
  def billing_active? = godfathered? || subscription&.access_granted? || false

  def owner_membership = memberships.find_by(role: :owner)
  def owner = owner_membership&.user

  # Godfathered workspaces have unlimited seats; otherwise the plan's limit.
  def seat_limit
    return Float::INFINITY if godfathered?

    subscription&.seat_limit || Pricing.seat_limit_for(:solo)
  end

  def within_seat_limit? = seat_count < seat_limit

  # Recomputes the `over_seat_limit` flag from the current membership count vs.
  # the plan's seat limit. Called after a subscription sync (e.g. a downgrade
  # applied outside the app, via the Stripe dashboard). Never removes members —
  # it only flags the workspace so writes are gated until the owner reconciles.
  def sync_seat_compliance!
    update!(over_seat_limit: seat_count > seat_limit)
  end

  def client_limit
    return Float::INFINITY if godfathered?

    Pricing.client_limit_for(plan)
  end

  def within_client_limit? = clients.count < client_limit

  # A godfathered workspace whose monthly generation credits are capped by staff.
  # (Godfathered without a cap = truly unlimited; non-godfathered ignore the cap.)
  def credit_limited? = godfathered? && monthly_credit_limit.present?

  # Spendable prepaid credits. Unlimited godfathered workspaces never debit; the
  # caller should treat their balance as infinite (see the serializer). Capped
  # godfathered workspaces spend from the monthly allotment like everyone else —
  # before the cycle's grant lands (fresh month) we report the full cap.
  def credits_available
    return credit_wallet&.available || 0 unless credit_limited?

    wallet = credit_wallet
    return monthly_credit_limit if wallet.nil?
    return wallet.available if wallet.granted_current?

    monthly_credit_limit + wallet.purchased_balance
  end

  # ── Plan-gated features ──────────────────────────────────────────────
  # Plan tier ordering (matches the Subscription#plan enum).
  PLAN_RANK = { 'solo' => 0, 'agencia' => 1, 'enterprise' => 2 }.freeze

  def plan_rank = PLAN_RANK.fetch(plan.to_s, 0)

  def plan_at_least?(tier) = plan_rank >= PLAN_RANK.fetch(tier.to_s, 999)

  # The Claude/MCP connector is an Agência+ feature (Solo sees an upgrade hook).
  # Godfathered workspaces get everything.
  def mcp_enabled? = godfathered? || plan_at_least?(:agencia)

  def self.ransackable_attributes(_auth = nil)
    %w[id name slug godfathered monthly_credit_limit over_seat_limit timezone locale created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil)
    %w[memberships users subscription setting credit_wallet clients projects
       generations invoices social_accounts]
  end
end
