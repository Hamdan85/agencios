# frozen_string_literal: true

module Vendors
  module Heygen
    module Actions
      # List available TTS voices. `GET /v2/voices` → each voice object carries
      # `voice_id`, `language`, `gender`, `name`, `preview_audio`, `support_pause`,
      # `emotion_support`. Returns the array of voices. Cache it.
      #
      # See docs/integrations/heygen.md §4.
      class ListVoices
        def self.call(...) = new(...).call

        def initialize(client: nil)
          @client = client || Client.new
        end

        def call
          body = @client.get("/v2/voices")
          data = body["data"] || {}
          data["voices"] || data || []
        end
      end
    end
  end
end
