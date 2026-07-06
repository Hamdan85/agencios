# frozen_string_literal: true

module Controllers
  module Public
    module Approvals
      class Show < Controllers::Base
        def initialize(ticket:)
          @ticket = ticket
        end

        def call
          {
            branding: branding,
            campaign: @ticket.project.name,
            title: @ticket.display_title,
            approved: @ticket.fully_approved?,
            creatives: serialize_collection(@ticket.approvable_creatives, CreativeSerializer),
            plan: { networks: @ticket.channels, planned_at: @ticket.scheduled_at&.iso8601 }
          }
        end

        private

        def branding
          ws = @ticket.workspace
          { name: ws.name, primary_color: ws.brand_primary_color, logo_url: logo_url(ws) }
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
