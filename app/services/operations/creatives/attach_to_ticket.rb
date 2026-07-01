# frozen_string_literal: true

module Operations
  module Creatives
    # Links a standalone Studio creative (no ticket yet) to a ticket, so it can
    # be used in that ticket's production/publishing flow.
    class AttachToTicket < Operations::Base
      def initialize(ticket:, creative:)
        @ticket = ticket
        @creative = creative
      end

      def call
        @creative.update!(ticket: @ticket)
        @creative
      end
    end
  end
end
