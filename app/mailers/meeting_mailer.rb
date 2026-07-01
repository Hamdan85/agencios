# frozen_string_literal: true

# Meeting invitations to attendees / the client (Google Calendar + Meet).
class MeetingMailer < ApplicationMailer
  # @param meeting [Meeting]
  # @param recipient_email [String]
  # @param recipient_name  [String, nil]
  def invitation(meeting:, recipient_email:, recipient_name: nil)
    @meeting = meeting
    @recipient_name = recipient_name
    @workspace = meeting.workspace
    @meet_url = meeting.meet_url
    mail(to: recipient_email, subject: "Reunião agendada: #{meeting.title} — #{email_datetime(meeting.starts_at)}")
  end
end
