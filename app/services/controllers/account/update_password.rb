# frozen_string_literal: true

module Controllers
  module Account
    # Changes the signed-in user's password. Requires the current password
    # (defense against a hijacked session) and a minimum-strength new one, then
    # sends the "your password changed" courtesy notice.
    class UpdatePassword < Base
      MIN_LENGTH = 8

      def initialize(params:)
        @params = params
      end

      def call
        current  = @params[:current_password].to_s
        password = @params[:password].to_s

        unless user.authenticate(current)
          raise Operations::Errors::Invalid, 'Senha atual incorreta.'
        end

        if password.length < MIN_LENGTH
          raise Operations::Errors::Invalid, "A nova senha deve ter ao menos #{MIN_LENGTH} caracteres."
        end

        user.update!(password: password)
        AuthMailer.password_changed(user: user).deliver_later
        { message: 'Senha alterada.' }
      end
    end
  end
end
