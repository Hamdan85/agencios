# frozen_string_literal: true

# Emails the workspace members @-mentioned in a comment (excluding the author).
# Recipients are resolved from the note's authoritative `mentioned_user_ids`.
class NotifyMentionsJob < ApplicationJob
  queue_as :default

  def perform(note_id)
    note = Note.find_by(id: note_id)
    return unless note
    return if note.mentioned_user_ids.blank?

    author = note.user&.display_name
    recipients(note).each do |recipient|
      NoteMailer.mention(note: note, recipient: recipient).deliver_later
      Operations::Push::Notify.call(
        user: recipient,
        title_key: author ? 'push.mention.title' : 'push.mention.title_anonymous',
        params: { author: author.to_s },
        body: note.display_body.to_s.delete('@').squish.truncate(120),
        path: "/tickets/#{note.ticket_id}"
      )
    rescue StandardError => e
      Rails.logger.warn("[NotifyMentionsJob] notify user #{recipient.id} failed: #{e.message}")
    end
  end

  private

  def recipients(note)
    note.workspace
        .memberships
        .where(user_id: note.mentioned_user_ids)
        .where.not(user_id: note.user_id)
        .includes(:user)
        .map(&:user)
  end
end
