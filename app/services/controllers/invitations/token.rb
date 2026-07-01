# frozen_string_literal: true

module Controllers
  module Invitations
    # Signing/verification for the table-free invite tokens.
    module Token
      VERIFIER = 'agencios:invitations'

      module_function

      def sign(payload)
        verifier.generate(payload.stringify_keys, expires_in: 7.days)
      end

      def verify(token)
        verifier.verify(token)
      rescue StandardError
        nil
      end

      def verifier
        Rails.application.message_verifier(VERIFIER)
      end
    end
  end
end
