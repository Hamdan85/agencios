# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: SystemConfig.mailer_from
  layout "mailer"

  # Make the branded-email building blocks (logo_url, email_button, email_brl,
  # status_label, …) available in templates (`helper`) and directly inside the
  # mailer actions (`include`) — e.g. to format a subject line. ActionMailer does
  # not auto-include app/helpers.
  helper MailerHelper
  include MailerHelper
end
