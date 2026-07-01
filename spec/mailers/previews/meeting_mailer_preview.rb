# frozen_string_literal: true

require_relative 'mailer_preview_data'

# Preview at /rails/mailers/meeting_mailer
class MeetingMailerPreview < ActionMailer::Preview
  def invitation
    MeetingMailer.invitation(
      meeting: MailerPreviewData.meeting,
      recipient_email: 'cliente@exemplo.com',
      recipient_name: 'Cris'
    )
  end
end
