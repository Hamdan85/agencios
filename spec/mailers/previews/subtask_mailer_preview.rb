# frozen_string_literal: true

require_relative "mailer_preview_data"

# Preview at /rails/mailers/subtask_mailer
class SubtaskMailerPreview < ActionMailer::Preview
  def assigned
    SubtaskMailer.assigned(
      subtask: MailerPreviewData.subtask,
      assignee: MailerPreviewData.user,
      actor: MailerPreviewData.user(name: "Rui Lima")
    )
  end
end
