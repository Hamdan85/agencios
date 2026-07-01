# frozen_string_literal: true

require_relative 'mailer_preview_data'

# Preview at /rails/mailers/auth_mailer
class AuthMailerPreview < ActionMailer::Preview
  def welcome
    AuthMailer.welcome(user: MailerPreviewData.user)
  end

  def confirm_email
    AuthMailer.confirm_email(user: MailerPreviewData.user, token: 'sample-token')
  end

  def password_reset
    AuthMailer.password_reset(user: MailerPreviewData.user, token: 'sample-token')
  end

  def password_changed
    AuthMailer.password_changed(user: MailerPreviewData.user)
  end
end
