# frozen_string_literal: true

module Controllers
  module PasswordResets
    # Always returns the same message to avoid leaking which emails exist.
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        user = User.find_by(email: @params[:email].to_s.strip.downcase)
        if user
          token = user.generate_token_for(:password_reset)
          AuthMailer.password_reset(user: user, token: token).deliver_later
        end
        { message: I18n.t('api.passwords.instructions_sent') }
      end
    end
  end
end
