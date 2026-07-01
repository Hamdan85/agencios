# frozen_string_literal: true

module Vendors
  module Heygen
    module Actions
      # Generate a branded UGC ad from a pre-built Studio template, filling its
      # named variables. `POST /v2/template/{template_id}/generate`.
      #
      # `variables` is keyed by variable name; each entry is
      # `{ name:, type:, properties: {...} }`. Variable types: text (`content`),
      # image (`url`|`asset_id`,`fit`), video, audio, voice (`voice_id`),
      # character (`character_id`,`type`). Returns the `video_id`.
      #
      # See docs/integrations/heygen.md §3c.
      class GenerateVideoFromTemplate
        def self.call(...) = new(...).call

        def initialize(template_id:, variables:, title: nil, caption: false,
                       dimension: { width: 1080, height: 1920 },
                       callback_id: nil, callback_url: nil, test: false, client: nil)
          @template_id  = template_id
          @variables    = variables
          @title        = title
          @caption      = caption
          @dimension    = dimension
          @callback_id  = callback_id
          @callback_url = callback_url
          @test         = test
          @client       = client || Client.new
        end

        def call
          payload = {
            variables: @variables,
            caption: @caption,
            dimension: @dimension,
            test: @test
          }
          payload[:title]        = @title if @title
          payload[:callback_id]  = @callback_id if @callback_id
          payload[:callback_url] = @callback_url if @callback_url

          body = @client.post("/v2/template/#{@template_id}/generate", payload)
          body.dig('data', 'video_id')
        end
      end
    end
  end
end
