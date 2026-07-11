# frozen_string_literal: true

# Account lifecycle emails: welcome, e-mail confirmation, password reset and
# the post-reset confirmation. Tokens are minted by the caller via
# `User#generates_token_for` (see app/models/user.rb).
class AuthMailer < ApplicationMailer
  # Sent right after registration (Operations::Users::Register).
  def welcome(user:)
    @user = user
    @board_url = app_host('/painel')
    with_recipient_locale(user) do
      mail(to: @user.email, subject: I18n.t('mailers.auth.welcome.subject'))
    end
  end

  # Confirm-your-email link. `token` from generates_token_for(:email_confirmation).
  def confirm_email(user:, token:)
    @user = user
    @confirm_url = app_host("/confirmar-email/#{token}")
    with_recipient_locale(user) do
      mail(to: @user.email, subject: I18n.t('mailers.auth.confirm_email.subject'))
    end
  end

  # Confirm-your-new-address link for an e-mail change. Sent TO the new address
  # (that's the whole point — proving the user owns it). `token` from
  # generates_token_for(:email_change).
  def confirm_email_change(user:, token:, new_email:)
    @user = user
    @new_email = new_email
    @confirm_url = app_host("/confirmar-troca-email/#{token}")
    with_recipient_locale(user) do
      mail(to: new_email, subject: I18n.t('mailers.auth.confirm_email_change.subject'))
    end
  end

  # Password reset link. `token` from generates_token_for(:password_reset) (20 min).
  def password_reset(user:, token:)
    @user = user
    @reset_url = app_host("/redefinir-senha/#{token}")
    with_recipient_locale(user) do
      mail(to: @user.email, subject: I18n.t('mailers.auth.password_reset.subject'))
    end
  end

  # Confirmation that the password was just changed (a security courtesy).
  def password_changed(user:)
    @user = user
    @support_url = app_host('/login')
    with_recipient_locale(user) do
      mail(to: @user.email, subject: I18n.t('mailers.auth.password_changed.subject'))
    end
  end

  private

  def app_host(path = '')
    "#{SystemConfig.app_host}#{path}"
  end
end
