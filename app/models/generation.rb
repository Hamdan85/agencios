# frozen_string_literal: true

# A creative-generation run.
#
# Customer billing is prepaid credits: `video`, `image`, and `carousel` kinds all
# consume credits (see Pricing#credits_for + Operations::Credits::Debit). The real
# vendor cost lives in `cost_cents` (+ the AiUsageLog trail); there is no Stripe
# usage metering (removed in favour of credits).
class Generation < ApplicationRecord
  belongs_to :workspace
  belongs_to :user, optional: true
  belongs_to :creative, optional: true

  enum :kind, { carousel: 0, video: 1, image: 2 }, prefix: true
  enum :status, { queued: 0, processing: 1, completed: 2, failed: 3 }, prefix: :status

  def self.ransackable_attributes(_auth = nil)
    %w[id workspace_id user_id creative_id kind status provider external_id
       cost_cents failure_reason created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil)
    %w[workspace user creative]
  end
end
