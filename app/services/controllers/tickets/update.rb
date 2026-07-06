# frozen_string_literal: true

module Controllers
  module Tickets
    # Plain attribute / contextual-field update. Status changes NEVER come through
    # here — only via Advance (Operations::Tickets::ChangeStatus).
    class Update < Base
      ATTRIBUTE_KEYS = %w[title assignee_id priority project_id due_date scheduled_at creative_type channels].freeze

      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:id])

        if @params.dig(:ticket, :fields).present?
          status = @params[:ticket][:status] || ticket.status
          Operations::Tickets::UpdateFields.call(
            ticket: ticket, status: status,
            values: @params[:ticket][:fields].to_unsafe_h
          )
          # A real content edit re-derives the LATER stages so they reflect the
          # change. Debounced by the updated_at token: a burst of autosaves
          # collapses to a single downstream regeneration (only the last one runs).
          # Leading :: — inside Controllers::Tickets a bare `Tickets::` would
          # resolve to Controllers::Tickets::CascadeFieldsJob (nonexistent).
          ::Tickets::CascadeFieldsJob.set(wait: 6.seconds).perform_later(
            ticket.id, status.to_s, ticket.updated_at.utc.iso8601(6)
          )
        end
        Operations::Tickets::Update.call(ticket: ticket, params: ticket_params) if attribute_update?

        Show.new(params: @params).call
      end

      private

      def attribute_update?
        @params[:ticket].present? &&
          (@params[:ticket].keys.map(&:to_s) & ATTRIBUTE_KEYS).any?
      end

      def ticket_params
        @params.require(:ticket).permit(
          :project_id, :title, :assignee_id, :priority, :due_date, :scheduled_at,
          :creative_type, channels: [], fields: {}
        )
      end
    end
  end
end
