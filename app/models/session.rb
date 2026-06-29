# frozen_string_literal: true

# Token-based auth session. The signed `session_id` cookie carries the token;
# the row carries the active tenant (workspace_id) and activity timers.
class Session < ApplicationRecord
  belongs_to :user
  belongs_to :workspace, optional: true

  ABSOLUTE_TTL   = 90.days
  IDLE_TTL       = 14.days
  TOUCH_THROTTLE = 5.minutes

  def self.generate_token
    SecureRandom.urlsafe_base64(32)
  end

  def expired?
    expires_at.present? && expires_at.past?
  end

  def touch_activity!
    return if last_active_at && last_active_at > TOUCH_THROTTLE.ago

    update_columns(last_active_at: Time.current, expires_at: IDLE_TTL.from_now)
  end
end
