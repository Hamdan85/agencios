# frozen_string_literal: true

module Vendors
  module Pexels
    # Free stock-photo source for carousel image slots.
    #
    # Endpoint: GET https://api.pexels.com/v1/search?query=...&orientation=...
    # Auth:     Authorization: <api_key> header (NOT Bearer).
    # Credentials: `pexels.api_key` / ENV PEXELS_API_KEY.
    #
    # Degrades gracefully: with no key (or on any API error) it returns [] so the
    # carousel simply falls back to brand-only / generated imagery.
    class Client < Vendors::Base
      BASE_URL = 'https://api.pexels.com'

      def initialize(api_key: nil)
        @api_key = api_key || credential(:pexels, :api_key, env: 'PEXELS_API_KEY')
      end

      def configured? = @api_key.present?

      # Returns an array of normalized photo hashes (possibly empty).
      def search(query:, per_page: 10, orientation: nil)
        return [] if @api_key.blank? || query.to_s.strip.blank?

        params = { query: query, per_page: per_page }
        params[:orientation] = orientation if orientation.present?

        body = handle(connection.get('/v1/search', params))
        Array(body['photos']).map { |photo| normalize(photo) }
      rescue Vendors::Base::Error => e
        Rails.logger.warn("[Vendors::Pexels] #{e.class}: #{e.message} — returning no photos.")
        []
      end

      private

      def connection
        @connection ||= build_connection(BASE_URL, headers: { 'Authorization' => @api_key.to_s })
      end

      def normalize(photo)
        src = photo['src'] || {}
        {
          id: photo['id'],
          url: src['large2x'] || src['large'] || src['original'],
          photographer: photo['photographer'],
          alt: photo['alt']
        }
      end
    end
  end
end
