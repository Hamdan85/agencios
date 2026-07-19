# frozen_string_literal: true

module Operations
  module Social
    # Marks a SocialAccount as needing reconnection after the network rejected
    # its token outright (Graph #190 & friends — see Meta::Client::DEAD_TOKEN_CODES).
    # The account keeps its rows and tokens: only the status moves, so the UI can
    # prompt a reconnect instead of the failure hiding in a job log.
    #
    # Idempotent by design — a metrics sweep hits every post of the same dead
    # account in one run, and only the first should write (and log).
    class FlagNeedsReauth < Operations::Base
      def initialize(social_account:, reason: nil)
        @account = social_account
        @reason = reason
      end

      def call
        return nil if @account.nil?
        return @account unless @account.status_connected?

        @account.update!(status: :needs_reauth)
        Rails.logger.warn(
          "[Social::FlagNeedsReauth] #{@account.provider} ##{@account.id} flagged: #{@reason}"
        )
        @account
      end
    end
  end
end
