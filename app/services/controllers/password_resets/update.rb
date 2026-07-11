# frozen_string_literal: true

module Controllers
  module PasswordResets
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        user = User.find_by_token_for(:password_reset, @params[:token])
        raise Operations::Errors::Invalid, I18n.t('api.passwords.invalid_token') unless user

        user.update!(password: @params.require(:password))
        AuthMailer.password_changed(user: user).deliver_later
        { message: I18n.t('api.passwords.reset_done') }
      end
    end
  end
end
