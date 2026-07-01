# frozen_string_literal: true

require_relative "mailer_preview_data"

# Preview at /rails/mailers/digest_mailer
class DigestMailerPreview < ActionMailer::Preview
  def daily_tickets
    DigestMailer.daily_tickets(user: MailerPreviewData.user, tickets: [MailerPreviewData.ticket])
  end

  def daily_tickets_empty
    DigestMailer.daily_tickets(user: MailerPreviewData.user, tickets: [])
  end
end
