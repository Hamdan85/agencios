# frozen_string_literal: true

module Controllers
  module PasswordResets
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        user = User.find_by_token_for(:password_reset, @params[:token])
        raise Operations::Errors::Invalid, "Token inválido ou expirado." unless user

        user.update!(password: @params.require(:password))
        AuthMailer.password_changed(user: user).deliver_later
        { message: "Senha redefinida." }
      end
    end
  end
end
