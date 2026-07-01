# frozen_string_literal: true

require_relative "mailer_preview_data"

# Preview at /rails/mailers/note_mailer
class NoteMailerPreview < ActionMailer::Preview
  def mention
    NoteMailer.mention(note: MailerPreviewData.note, recipient: MailerPreviewData.user)
  end
end
