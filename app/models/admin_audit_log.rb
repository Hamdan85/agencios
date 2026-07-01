# frozen_string_literal: true

# One row per platform-staff override/support action (impersonation, godfathered
# toggle, manual credit grant/comp). Written from the ActiveAdmin layer via
# `.record`. Read-only in the panel.
class AdminAuditLog < ApplicationRecord
  belongs_to :staff_user, class_name: 'User', optional: true
  belongs_to :target, polymorphic: true, optional: true

  scope :recent_first, -> { order(created_at: :desc) }

  def self.record(staff_user:, action:, target: nil, metadata: {}, ip_address: nil)
    create!(
      staff_user: staff_user,
      action: action,
      target_type: target&.class&.name,
      target_id: target&.id,
      metadata: metadata,
      ip_address: ip_address
    )
  rescue StandardError => e
    Rails.logger.warn("[AdminAuditLog] failed to record #{action}: #{e.message}")
    nil
  end

  def self.ransackable_attributes(_auth = nil)
    %w[id staff_user_id action target_type target_id ip_address created_at]
  end

  def self.ransackable_associations(_auth = nil)
    %w[staff_user target]
  end
end
