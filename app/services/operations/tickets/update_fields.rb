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

      # A few field values are also first-class ticket columns. `creative_types` is
      # the multi-select source; `creative_type` mirrors its first entry so board
      # chips / filters (which read the single column) keep working.
      def mirrored_columns(clean)
        cols = {}
        if clean.key?("creative_types")
          types = Array(clean["creative_types"]).map(&:to_s).compact_blank
          cols[:creative_types] = types
          cols[:creative_type] = types.first
        elsif clean.key?("creative_type")
          cols[:creative_type] = clean["creative_type"]
          cols[:creative_types] = Array(clean["creative_type"]).map(&:to_s).compact_blank
        end
        cols[:channels] = Array(clean["channels"]).compact_blank if clean.key?("channels")
        cols[:scheduled_at] = clean["scheduled_at"] if clean.key?("scheduled_at")
        cols[:due_date] = clean["due_date"] if clean.key?("due_date")
        cols
      end
    end
  end
end
