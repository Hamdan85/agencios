# frozen_string_literal: true

# Account lifecycle emails: welcome, e-mail confirmation, password reset and
# the post-reset confirmation. Tokens are minted by the caller via
# `User#generates_token_for` (see app/models/user.rb).
class AuthMailer < ApplicationMailer
  # Sent right after registration (Operations::Users::Register).
  def welcome(user:)
    @user = user
    @board_url = app_host('/painel')
    mail(to: @user.email, subject: 'Bem-vindo à agencios 🎉')
  end

  # Confirm-your-email link. `token` from generates_token_for(:email_confirmation).
  def confirm_email(user:, token:)
    @user = user
    @confirm_url = app_host("/confirmar-email/#{token}")
    mail(to: @user.email, subject: 'Confirme seu e-mail na agencios')
  end

  # Confirm-your-new-address link for an e-mail change. Sent TO the new address
  # (that's the whole point — proving the user owns it). `token` from
  # generates_token_for(:email_change).
  def confirm_email_change(user:, token:, new_email:)
    @user = user
    @new_email = new_email
    @confirm_url = app_host("/confirmar-troca-email/#{token}")
    mail(to: new_email, subject: 'Confirme seu novo e-mail na agencios')
  end

  # Password reset link. `token` from generates_token_for(:password_reset) (20 min).
  def password_reset(user:, token:)
    @user = user
    @reset_url = app_host("/redefinir-senha/#{token}")
    mail(to: @user.email, subject: 'Redefinição de senha — agencios')
  end

  # Confirmation that the password was just changed (a security courtesy).
  def password_changed(user:)
    @user = user
    @support_url = app_host('/login')
    mail(to: @user.email, subject: 'Sua senha foi alterada')
  end

  private

  def app_host(path = '')
    "#{SystemConfig.app_host}#{path}"
  end
end
