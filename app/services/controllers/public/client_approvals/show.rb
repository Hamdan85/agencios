# frozen_string_literal: true

module Controllers
  module Public
    module ClientApprovals
      # The portal payload: the agency's brand, the client, and the queue of
      # tickets awaiting this client's approval (each with the scope the client
      # needs to decide + the creatives to review).
      class Show < Controllers::Base
        def initialize(client:)
          @client = client
        end

        def call
          {
            agency: agency,
            client: { name: @client.name },
            tickets: @client.pending_approval_tickets.map { |ticket| ticket_payload(ticket) }
          }
        end

        private

        def agency
          ws = @client.workspace
          { name: ws.name, primary_color: @client.brand_primary_color.presence || ws.brand_primary_color,
            logo_url: logo_url(ws) }
        end

        def ticket_payload(ticket)
          ideation = ticket.fields_for('ideation') || {}
          {
            id: ticket.id,
            title: ticket.display_title,
            campaign: ticket.project.name,
            objective: ideation['objective'],
            brief: ideation['brief'],
            channels: ticket.channels,
            creative_types: ticket.creative_types_list,
            scheduled_at: ticket.scheduled_at&.iso8601,
            slots: ticket.approval_slots.map { |type, options| slot_payload(type, options) }
          }
        end

        # A media-type slot: its label, derived decision state, the chosen winner (if
        # any), and the candidate options (each carrying its position for the UI).
        def slot_payload(creative_type, options)
          {
            creative_type: creative_type,
            label: ::Creatives.spec_for(creative_type)&.dig(:label) || creative_type,
            state: slot_state(options),
            chosen_creative_id: options.find(&:approval_approved?)&.id,
            options: options.each_with_index.map do |creative, index|
              serialize(creative, CreativeSerializer).merge(option_index: index, option_count: options.size)
            end
          }
        end

        def slot_state(options)
          return 'changes_requested' if options.any?(&:approval_changes_requested?)
          return 'approved' if options.any?(&:approval_approved?)

          'pending'
        end

        def logo_url(ws)
          return nil unless ws.logo.attached?

          Rails.application.routes.url_helpers.rails_blob_url(ws.logo, host: SystemConfig.app_host)
        rescue StandardError
          nil
        end
      end
    end
  end
end
