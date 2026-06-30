# frozen_string_literal: true

# A dated snapshot of one social account's profile-level analytics. Mirrors
# PostMetric, but at the account (not post) level. Written by
# Operations::Social::SyncAccountInsights; read by the project report aggregator.
class AccountMetric < ApplicationRecord
  belongs_to :social_account
  belongs_to :workspace

  scope :recent, -> { order(captured_at: :desc) }

  # The latest snapshot captured at or before `time` (used to read the value as it
  # stood at a report's period boundary).
  scope :as_of, ->(time) { where(captured_at: ..time).order(captured_at: :desc) }
end
