# frozen_string_literal: true

require_relative "mailer_preview_data"

# Preview at /rails/mailers/invitation_mailer
class InvitationMailerPreview < ActionMailer::Preview
  def invite
    InvitationMailer.invite(
      email: "novo@exemplo.com",
      role: "manager",
      link: "#{SystemConfig.app_host}/convite/sample-token",
      workspace: MailerPreviewData.workspace,
      inviter: MailerPreviewData.user(name: "Rui Lima")
    )
  end
end
