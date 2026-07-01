# frozen_string_literal: true

# Mentions in ticket comments. Other ticket mail (assignments, etc.) can live
# here too as it grows.
class NoteMailer < ApplicationMailer
  # Notifies a member that they were @-mentioned in a ticket comment.
  def mention(note:, recipient:)
    @note = note
    @recipient = recipient
    @ticket = note.ticket
    @author_name = note.user&.display_name || 'Alguém'
    @ticket_url = "#{SystemConfig.app_host}/tickets/#{@ticket.id}"

    mail(
      to: recipient.email,
      subject: "#{@author_name} mencionou você em \"#{@ticket.display_title}\""
    )
  end
end
