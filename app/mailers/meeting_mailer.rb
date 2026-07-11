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
    @brand_workspace = @workspace
    @meet_url = meeting.meet_url
    # Recipient is an email string (a client or an external attendee); render in
    # the meeting's client locale when there is one, otherwise the workspace's.
    with_recipient_locale(meeting.client || @workspace) do
      mail(to: recipient_email,
           subject: I18n.t('mailers.meeting.invitation.subject',
                           title: meeting.title, datetime: email_datetime(meeting.starts_at)))
    end
  end
end
