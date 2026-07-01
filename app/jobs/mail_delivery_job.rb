# frozen_string_literal: true

# Delivery job for all mailers. Mirrors ApplicationJob's resilience: mailer
# arguments are GlobalID-serialized records (e.g. the mention recipient), and a
# record can be deleted between enqueue and perform — discard rather than retry
# forever on the resulting DeserializationError.
class MailDeliveryJob < ActionMailer::MailDeliveryJob
  discard_on ActiveJob::DeserializationError
end
