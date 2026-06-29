# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  private

  # Billing gate for background work — true (and logs) when the owning workspace
  # is NOT billing-active, so callers can early-return.
  def skip_inactive?(workspace)
    return false if workspace&.billing_active?

    Rails.logger.info("[#{self.class.name}] skipped — workspace #{workspace&.id} billing inactive.")
    true
  end
end
