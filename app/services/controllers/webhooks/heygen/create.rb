# frozen_string_literal: true

module Controllers
  module Webhooks
    module Heygen
      # Verifies the signature, finds the Generation by external_id, and finalizes
      # (download + attach + meter) or marks it failed. Returns the HTTP status
      # symbol the controller should head (:unauthorized on a bad signature).
      class Create < Controllers::Base
        def initialize(signature:, payload:, params:)
          @signature = signature
          @payload = payload
          @params = params
        end

        def call
          return :unauthorized unless Vendors::Heygen::Webhook.verify(@payload, @signature)

          generation = Generation.find_by(external_id: video_id) if video_id.present?
          if generation && status.match?(/success|completed|ready/)
            Operations::Creatives::FinalizeGeneration.call(generation: generation, video_url: data[:video_url] || data[:url])
          elsif generation && status.match?(/fail|error/)
            generation.update!(status: :failed, failure_reason: data[:msg].to_s)
          end
          :ok
        end

        private

        def data
          @data ||= @params[:event_data] || @params[:data] || @params
        end

        def video_id
          data[:video_id] || data[:id]
        end

        def status
          @status ||= (data[:status] || @params[:event_type]).to_s
        end
      end
    end
  end
end
