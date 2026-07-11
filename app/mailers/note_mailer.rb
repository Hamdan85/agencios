# frozen_string_literal: true

# Mentions in ticket comments. Other ticket mail (assignments, etc.) can live
# here too as it grows.
class NoteMailer < ApplicationMailer
  # Notifies a member that they were @-mentioned in a ticket comment.
  def mention(note:, recipient:)
    @note = note
    @recipient = recipient
    @ticket = note.ticket
    @ticket_url = "#{SystemConfig.app_host}/tickets/#{@ticket.id}"

    with_recipient_locale(recipient) do
      @author_name = note.user&.display_name || I18n.t('mailers.note.mention.someone')
      mail(
        to: recipient.email,
        subject: I18n.t('mailers.note.mention.subject', author: @author_name, title: @ticket.display_title)
      )
    end
  end
end
