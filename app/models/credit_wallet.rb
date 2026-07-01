# frozen_string_literal: true

# A workspace's prepaid credit balance. Video + image generation debit credits;
# carousels and AI text are free. Two buckets:
#   * granted   — the monthly plan allotment; expires at the period end (use it
#                 or lose it). Spent FIRST.
#   * purchased — top-up packs; roll over (12 months). Spent after granted.
#
# The balance columns are authoritative and mutated transactionally; every change
# also appends a CreditTransaction for the audit trail. All mutating methods must
# be called inside the caller's transaction and take a row lock (see
# Operations::Credits::*), never mutated ad hoc.
class CreditWallet < ApplicationRecord
  belongs_to :workspace

  has_many :credit_transactions, through: :workspace

  # Credits currently spendable — granted only if the grant hasn't expired.
  def available
    live_granted + purchased_balance
  end

  # Granted credits, treating an elapsed grant window as zero (lazy expiry).
  def live_granted
    return 0 if granted_expires_at.present? && granted_expires_at.past?

    granted_balance
  end

  def granted_expired? = granted_expires_at.present? && granted_expires_at.past? && granted_balance.positive?

  def self.ransackable_attributes(_auth = nil)
    %w[id workspace_id granted_balance purchased_balance granted_expires_at created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil)
    %w[workspace]
  end
end
