# frozen_string_literal: true

require_relative "mailer_preview_data"

# Preview at /rails/mailers/ticket_mailer
class TicketMailerPreview < ActionMailer::Preview
  def assigned
    TicketMailer.assigned(
      ticket: MailerPreviewData.ticket,
      assignee: MailerPreviewData.user,
      actor: MailerPreviewData.user(name: "Rui Lima")
    )
  end
end
