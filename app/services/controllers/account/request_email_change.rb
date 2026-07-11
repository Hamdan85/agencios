# frozen_string_literal: true

module Controllers
  module Account
    # Starts an e-mail change: verifies the current password, stashes the new
    # address as `pending_email`, and mails a confirmation link to it. The change
    # only lands once the user clicks that link (ConfirmEmailChange) — so we
    # verify the user owns the new inbox before switching.
    class RequestEmailChange < Base
      def initialize(params:)
        @params = params
      end

      def call
        new_email = @params[:email].to_s.strip.downcase

        raise Operations::Errors::Invalid, I18n.t('api.account.wrong_current_password') unless user.authenticate(@params[:password].to_s)
        raise Operations::Errors::Invalid, I18n.t('api.account.invalid_email') unless new_email.match?(URI::MailTo::EMAIL_REGEXP)
        raise Operations::Errors::Invalid, I18n.t('api.account.email_unchanged') if new_email == user.email
        if User.where.not(id: user.id).exists?(email: new_email)
          raise Operations::Errors::Invalid, I18n.t('api.account.email_taken')
        end

        user.update!(pending_email: new_email)
        token = user.generate_token_for(:email_change)
        AuthMailer.confirm_email_change(user: user, token: token, new_email: new_email).deliver_later

        { message: I18n.t('api.account.confirmation_link_sent'), pending_email: new_email }
      end
    end
  end
end
