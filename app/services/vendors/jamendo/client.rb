# frozen_string_literal: true

module Vendors
  # Jamendo — an OPEN music base (royalty-free / Creative Commons) with a real
  # search API. The video orchestrator crafts a search query + mood tags; we
  # search here and get back a downloadable MP3 URL to burn under the video.
  #
  # App-level `client_id` in credentials (`jamendo.client_id`), ENV fallback.
  # Docs: https://developer.jamendo.com/v3.0/tracks
  module Jamendo
    class Client < Vendors::Base
      BASE_URL = 'https://api.jamendo.com'

      def initialize(client_id: nil)
        @client_id = client_id || credential(:jamendo, :client_id, env: 'JAMENDO_CLIENT_ID')
      end

      def configured? = @client_id.present?

      # Search tracks. Returns normalized hashes (best first):
      #   { id:, title:, artist:, url:, download_url:, license:, attribution:, duration: }
      # `query` = free text; `tags` = mood/genre tag(s); instrumental avoids vocals
      # clashing with the dialogue.
      def search(query:, tags: nil, limit: 5, instrumental: true)
        require_credential!(@client_id, 'jamendo.client_id')

        params = {
          client_id: @client_id, format: 'json', limit: limit,
          order: 'popularity_total', audioformat: 'mp32', include: 'musicinfo licenses',
          imagesize: 200, search: query.to_s.strip
        }
        params[:fuzzytags] = tags.to_s.strip if tags.present?
        params[:vocalinstrumental] = 'instrumental' if instrumental

        body = handle(connection.get('/v3.0/tracks', params))
        Array(body.is_a?(Hash) ? body['results'] : nil).filter_map { |t| normalize(t) }
      end

      private

      def connection
        @connection ||= build_connection(BASE_URL)
      end

      def normalize(track)
        url = track['audiodownload'].presence || track['audio'].presence
        return nil if url.blank?

        artist = track['artist_name'].to_s.strip
        title  = track['name'].to_s.strip
        {
          id: track['id'].to_s,
          title: title.presence,
          artist: artist.presence,
          url: url,
          download_url: track['audiodownload'].presence,
          license: track['license_ccurl'].presence,
          attribution: [title.presence, artist.presence].compact.join(' — ').presence,
          duration: track['duration'].to_i
        }
      end
    end
  end
end
