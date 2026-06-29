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
          # In production: PasswordMailer.reset(user, token).deliver_later
          Rails.logger.info("[PasswordReset] token for #{user.email}: #{token}")
        end
        { message: "Se o e-mail existir, enviaremos instruções." }
      end
    end
  end
end
