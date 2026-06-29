# frozen_string_literal: true

# A creative-generation run. `carousel` and `video` kinds are the usage-based
# billing meters (Stripe). Image is tracked but not metered.
class Generation < ApplicationRecord
  belongs_to :workspace
  belongs_to :user, optional: true
  belongs_to :creative, optional: true

  enum :kind, { carousel: 0, video: 1, image: 2 }, prefix: true
  enum :status, { queued: 0, processing: 1, completed: 2, failed: 3 }, prefix: :status

  def metered? = metered_at.present?
  def billable? = kind_carousel? || kind_video?
end
