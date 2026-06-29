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
          Operations::Tickets::UpdateFields.call(
            ticket: ticket, status: @params[:ticket][:status] || ticket.status,
            values: @params[:ticket][:fields].to_unsafe_h
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
