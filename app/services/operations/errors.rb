# frozen_string_literal: true

module Operations
  module Errors
    class Error < StandardError; end

    # Caller tried something the current membership role can't do.
    class Forbidden < Error; end

    # Inviting/adding a seat past the plan's seat limit.
    class SeatLimitReached < Error
      def initialize(msg = I18n.t('operations.errors.seat_limit_reached'))
        super
      end
    end

    # Creating/reactivating a client past the plan's active-client limit.
    class ClientLimitReached < Error
      def initialize(msg = I18n.t('operations.errors.client_limit_reached'))
        super
      end
    end

    # Workspace billing is not active and the action requires it.
    class BillingRequired < Error
      def initialize(msg = I18n.t('operations.errors.billing_required'))
        super
      end
    end

    # Not enough prepaid credits for a video/image generation.
    class InsufficientCredits < Error
      attr_reader :required, :available

      def initialize(required: nil, available: nil)
        @required = required
        @available = available
        super(I18n.t('operations.errors.insufficient_credits'))
      end
    end

    # An invalid ticket status transition was requested.
    class InvalidTransition < Error; end

    # A required validation failed inside an operation.
    class Invalid < Error; end
  end
end
