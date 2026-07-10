# frozen_string_literal: true

# Append-only ledger of every credit movement (grant, purchase, debit, refund,
# expire, adjustment). `amount` is signed (+ adds credits, − spends them);
# `granted_delta` / `purchased_delta` record how the two wallet buckets moved so
# a refund can return credits to the exact buckets they came from.
class CreditTransaction < ApplicationRecord
  belongs_to :workspace
  belongs_to :generation, optional: true
  belongs_to :user, optional: true

  KINDS   = %w[grant purchase debit refund expire adjustment].freeze
  BUCKETS = %w[granted purchased mixed].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :bucket, inclusion: { in: BUCKETS }

  scope :recent_first, -> { order(created_at: :desc) }

  # Ledger copy stored as i18n key renders in the CURRENT locale; legacy rows
  # (and custom admin descriptions) fall back to the stored text.
  def display_description
    return description if description_key.blank?

    I18n.t(description_key, **description_params.symbolize_keys, default: description || description_key)
  end
  scope :debits, -> { where(kind: 'debit') }

  def self.ransackable_attributes(_auth = nil)
    %w[id workspace_id generation_id user_id kind bucket amount granted_delta
       purchased_delta balance_after expires_at description created_at]
  end

  def self.ransackable_associations(_auth = nil)
    %w[workspace generation user]
  end
end
