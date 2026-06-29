# frozen_string_literal: true

module Operations
  module Tickets
    # Writes the status-scoped structured field bag (ticket.fields[status]) plus
    # any mirrored top-level columns (creative_type, channels, scheduled_at, …).
    class UpdateFields < Operations::Base
      def initialize(ticket:, status:, values:)
        @ticket = ticket
        @status = status.to_s
        @values = values || {}
      end

      def call
        clean = ::Tickets::Fields.sanitize(@status, @values.stringify_keys)
        merged = @ticket.fields.merge(@status => @ticket.fields_for(@status).merge(clean))

        attrs = { fields: merged }
        attrs.merge!(mirrored_columns(clean))

        @ticket.update!(attrs)
        Broadcaster.ticket(@ticket, "ticket_updated", status: @ticket.status)
        @ticket
      end

      private

      # A few field values are also first-class ticket columns.
      def mirrored_columns(clean)
        cols = {}
        cols[:creative_type] = clean["creative_type"] if clean.key?("creative_type")
        cols[:channels] = Array(clean["channels"]).compact_blank if clean.key?("channels")
        cols[:scheduled_at] = clean["scheduled_at"] if clean.key?("scheduled_at")
        cols[:due_date] = clean["due_date"] if clean.key?("due_date")
        cols
      end
    end
  end
end
