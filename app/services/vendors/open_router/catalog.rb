# frozen_string_literal: true

module Vendors
  module OpenRouter
    # Read-only client for OpenRouter's public model catalog, powering the admin
    # model pickers. Text models come from GET /api/v1/models (text-only
    # `architecture.output_modalities`); image engines have their own list at
    # GET /api/v1/images/models (what Vendors::OpenRouter::Image generates
    # through) and video engines at GET /api/v1/videos/models. All public — no
    # API key needed.
    #
    # The full per-kind list is cached briefly so typeahead searches don't hit
    # OpenRouter on every keystroke; search/pagination happen in-process
    # (Actions::ListModels).
    class Catalog < Vendors::Base
      BASE_URL  = 'https://openrouter.ai'
      KINDS     = %w[text image video].freeze
      CACHE_TTL = 10.minutes

      # The auto-router isn't a concrete image engine — selecting it for image
      # generation is exactly the "no endpoints" trap the picker exists to avoid.
      IMAGE_EXCLUDED_IDS = %w[openrouter/auto].freeze

      # Normalized catalog for a kind: [{ id:, name: }] in OpenRouter's order
      # (newest first). Raises Vendors::Base::Error on HTTP failure.
      def models(kind:)
        raise ArgumentError, "unknown model kind: #{kind}" unless KINDS.include?(kind.to_s)

        Rails.cache.fetch("openrouter_catalog/#{kind}", expires_in: CACHE_TTL) do
          case kind.to_s
          when 'video' then video_models
          when 'image' then image_models
          else text_models
          end
        end
      end

      private

      def video_models
        normalize(handle(connection.get('/api/v1/videos/models'))['data'])
      end

      def image_models
        entries = handle(connection.get('/api/v1/images/models'))['data']
        normalize(Array(entries).reject { |m| IMAGE_EXCLUDED_IDS.include?(m['id']) })
      end

      def text_models
        entries = handle(connection.get('/api/v1/models'))['data']
        entries = Array(entries).select do |m|
          out = m.dig('architecture', 'output_modalities') || []
          out.include?('text') && out.exclude?('image')
        end
        normalize(entries)
      end

      def normalize(entries)
        Array(entries).filter_map do |m|
          id = m['id'].to_s
          next if id.blank?

          { id: id, name: m['name'].to_s.presence || id }
        end
      end

      def connection
        @connection ||= build_connection(BASE_URL)
      end
    end
  end
end
