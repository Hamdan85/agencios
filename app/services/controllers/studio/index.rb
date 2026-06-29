# frozen_string_literal: true

module Controllers
  module Studio
    # Creative studio landing: the type picker + the agency's clients (each with
    # its OWN brand) + recent generations. Brand context is per CLIENT — the studio
    # generates content FOR a client, so it carries the client's brand, not the
    # workspace's.
    class Index < Base
      def call
        {
          creative_types: ::Creatives.all_specs,
          clients: clients_payload,
          recent_generations: serialize_collection(recent_generations, GenerationSerializer)
        }
      end

      private

      def clients_payload
        workspace.clients.status_active.order(:name).map do |client|
          {
            id: client.id,
            name: client.name,
            brand: {
              handle: client.default_handle,
              primary: client.brand_primary_color,
              secondary: client.brand_secondary_color,
              voice: client.brand_voice,
              logo_url: blob_url(client.logo),
              avatar_url: blob_url(client.default_creator_avatar)
            }
          }
        end
      end

      def blob_url(attachment)
        return nil unless attachment.attached?

        Rails.application.routes.url_helpers.rails_blob_url(attachment, host: SystemConfig.app_host)
      rescue StandardError
        nil
      end

      def recent_generations
        workspace.generations.order(created_at: :desc).limit(12)
      end
    end
  end
end
