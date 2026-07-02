# frozen_string_literal: true

module Controllers
  module Account
    # Applies a pending e-mail change from the token in the confirmation link.
    # Public (the user clicks it from their inbox, possibly signed out), so it
    # resolves the user from the token rather than from `Current`.
    class ConfirmEmailChange < Base
      def initialize(params:)
        @params = params
      end

      def call
        target = User.find_by_token_for(:email_change, @params[:token].to_s)
        raise Operations::Errors::Invalid, 'Link inválido ou expirado.' if target.nil? || target.pending_email.blank?

        new_email = target.pending_email
        if User.where.not(id: target.id).exists?(email: new_email)
          target.update!(pending_email: nil)
          raise Operations::Errors::Invalid, 'Este e-mail já está em uso.'
        end

        # Changing the address re-verifies ownership, so the account is confirmed.
        target.update!(email: new_email, pending_email: nil, confirmed_at: Time.current)
        { message: 'E-mail confirmado e atualizado.', email: new_email }
      end
    end
  end
end
