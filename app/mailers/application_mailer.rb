# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: SystemConfig.mailer_from
  layout 'mailer'

  # Discard delivery when a GlobalID-serialized argument (e.g. the mention
  # recipient) no longer exists at perform time, instead of failing forever.
  self.delivery_job = MailDeliveryJob

  # Make the branded-email building blocks (logo_url, email_button, email_brl,
  # status_label, …) available in templates (`helper`) and directly inside the
  # mailer actions (`include`) — e.g. to format a subject line. ActionMailer does
  # not auto-include app/helpers.
  helper MailerHelper
  include MailerHelper

  private

  # Every mailer runs outside the request cycle, so no locale is set. Render each
  # message (subject + body) in the RECIPIENT's own language: users get their
  # `users.locale`, clients their `clients.locale`, and email-string-only sends
  # fall back to the workspace/client passed as `record`. Wrap the whole `mail`
  # call (the subject is evaluated eagerly, the body lazily — both need to be
  # inside the block).
  def with_recipient_locale(record, &block)
    I18n.with_locale(resolve_recipient_locale(record), &block)
  end

  def resolve_recipient_locale(record)
    candidate = record.try(:locale).to_s
    I18n.available_locales.find { |l| l.to_s == candidate } || I18n.default_locale
  end
end
