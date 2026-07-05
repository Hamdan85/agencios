# frozen_string_literal: true

module Vendors
  # Epidemic Sound — a LICENSED music catalog (not royalty-free/CC) consumed
  # through its **MCP server** (Streamable HTTP / JSON-RPC 2.0), NOT a plain REST
  # API. The video orchestrator crafts a natural-language brief; we search the
  # catalog (`SearchRecordings`) and resolve a burnable download URL
  # (`DownloadRecording`) to mix under the video.
  #
  # IMPORTANT: the real MCP tools are `SearchRecordings` / `DownloadRecording`
  # (GraphQL-shaped), NOT the `search_music` / `download_music_track` names in the
  # marketing docs. Search works on any key; DOWNLOAD requires an entitled account
  # (an unentitled key gets a FORBIDDEN error → search yields no burnable track and
  # Vendors::Music falls back to the admin catalog). That is why Jamendo is the
  # default provider until this account is entitled.
  #
  # App-level API key in credentials (`epidemic_sound.api_key`), ENV fallback.
  # NOTE: keys are valid for 30 days and must be regenerated.
  # Docs: https://developers.epidemicsound.com/docs/mcp/
  #       https://developers.epidemicsound.com/docs/soundtracking-with-llm/
  module EpidemicSound
    class Client < Vendors::Base
      ENDPOINT         = 'https://www.epidemicsound.com/a/mcp-service/mcp'
      PROTOCOL_VERSION = '2025-06-18'
      CLIENT_INFO      = { name: 'agencios', version: '1.0' }.freeze

      def initialize(api_key: nil)
        @api_key = api_key || credential(:epidemic_sound, :api_key, env: 'EPIDEMIC_SOUND_API_KEY')
        @rpc_id  = 0
      end

      def configured? = @api_key.present?

      # Search the catalog and return the BEST fully-resolved track as a one-item
      # array (normalized, downloadable). Mirrors the previous Jamendo contract:
      #   { id:, title:, artist:, url:, download_url:, license:, attribution:, duration: }
      # `query` = free text; `tags` = mood/genre; `instrumental` avoids vocals
      # clashing with the dialogue. Epidemic's search is SEMANTIC, so we fold the
      # mood + instrumental hint into one natural-language brief.
      def search(query:, tags: nil, limit: 5, instrumental: true)
        require_credential!(@api_key, 'epidemic_sound.api_key')

        args = { query: { topic: semantic_brief(query, tags) }, first: limit }
        args[:filter] = { vocals: false } if instrumental
        recordings = recordings_from(call_tool('SearchRecordings', args))

        recordings.first(limit).each do |rec|
          id = string_value(rec, 'id')
          next if id.blank?

          url = resolve_download(id)
          next if url.blank?

          return [normalize(rec, url)]
        end
        []
      end

      private

      # ---- catalog helpers ---------------------------------------------------

      # `SearchRecordings.query` is one of { term, topic, externalID }; `topic` is
      # the SEMANTIC natural-language option, which Epidemic recommends over
      # structured filters — so fold the mood into one flowing brief (≤500 chars).
      def semantic_brief(query, tags)
        [query.to_s.strip, tags.to_s.strip].reject(&:blank?).join(', ').slice(0, 500)
      end

      # Unwrap the GraphQL-shaped result: data.recordings.nodes[].recording.
      def recordings_from(payload)
        return [] unless payload.is_a?(Hash)

        nodes = payload.dig('data', 'recordings', 'nodes')
        Array(nodes).filter_map { |n| n.is_a?(Hash) ? (n['recording'] || n) : nil }
      end

      # Ask for a production-ready FULL MP3 and pull the direct URL out. DOWNLOAD
      # IS ENTITLEMENT-GATED: an unentitled key raises FORBIDDEN here — swallowed
      # so the track is simply skipped (Vendors::Music falls back to the catalog).
      def resolve_download(recording_id)
        payload = call_tool('DownloadRecording',
                            { id: recording_id, options: { fileType: 'MP3', stemType: 'FULL' } })
        extract_url(payload)
      rescue Vendors::Base::Error => e
        Rails.logger.warn("[EpidemicSound] download denied for #{recording_id}: #{e.message.to_s[0, 120]}")
        nil
      end

      # The download result shape isn't observable without entitlement, so probe
      # the common direct keys and the GraphQL `data.recordingDownload` envelope.
      def extract_url(payload)
        return payload if payload.is_a?(String) && payload.start_with?('http')
        return nil unless payload.is_a?(Hash)

        node = payload.dig('data', 'recordingDownload') || payload.dig('data', 'download') || payload
        node = payload unless node.is_a?(Hash)
        %w[url downloadUrl download_url signedUrl audioUrl mp3].filter_map { |k| node[k].presence }.first
      end

      # Map a recording to the shared track contract. Artist = the MAIN_ARTIST
      # credit; duration from audioFile (ms → s); cover art carried for the UI.
      def normalize(rec, url)
        title  = string_value(rec, 'title')
        artist = main_artist(rec)
        ms     = rec.dig('audioFile', 'durationInMilliseconds').to_i

        {
          id: string_value(rec, 'id'),
          title: title.presence,
          artist: artist.presence,
          url: url,
          download_url: url,
          image_url: string_value(rec, 'coverArtUrl').presence,
          license: 'Epidemic Sound',
          attribution: [title.presence, artist.presence].compact.join(' — ').presence,
          duration: ms.positive? ? (ms / 1000.0).round : 0
        }
      end

      def main_artist(rec)
        credits = Array(rec['credits'])
        main = credits.find { |c| c.is_a?(Hash) && c['role'].to_s.upcase == 'MAIN_ARTIST' } || credits.first
        main.is_a?(Hash) ? main.dig('artist', 'name').to_s.strip : ''
      end

      def string_value(hash, *keys)
        keys.each do |k|
          v = hash[k]
          return v.to_s.strip if v.present?
        end
        ''
      end

      # ---- MCP transport (JSON-RPC 2.0 over Streamable HTTP) -----------------

      # Open a session once per client instance, then dispatch a `tools/call` and
      # unwrap the tool's structured result.
      def call_tool(name, arguments)
        ensure_session!
        result = rpc('tools/call', { name: name, arguments: arguments })
        tool_payload(result)
      end

      def ensure_session!
        return if @initialized

        rpc('initialize', {
          protocolVersion: PROTOCOL_VERSION,
          capabilities: {},
          clientInfo: CLIENT_INFO
        })
        rpc('notifications/initialized', nil, notification: true)
        @initialized = true
      end

      # A single JSON-RPC round-trip. Captures the session id off `initialize`,
      # returns the parsed `result` (nil for notifications).
      def rpc(method, params = nil, notification: false)
        payload = { jsonrpc: '2.0', method: method }
        payload[:id]     = (@rpc_id += 1) unless notification
        payload[:params] = params if params

        response = connection.post do |req|
          req.body = payload
          req.headers['Mcp-Session-Id'] = @session_id if @session_id
        end
        raise_on_error!(response)

        session = response.headers['mcp-session-id'] || response.headers['Mcp-Session-Id']
        @session_id = session if session.present?
        notification ? nil : rpc_result(response)
      end

      # A tool result carries either `structuredContent` (preferred) or a list of
      # content blocks; the JSON we want is in the first text block.
      def tool_payload(result)
        return nil unless result.is_a?(Hash)

        raise Error, tool_error(result) if result['isError']
        return result['structuredContent'] if result['structuredContent'].present?

        text = Array(result['content']).filter_map { |c| c['text'] if c.is_a?(Hash) }.first
        parse_maybe_json(text)
      end

      def tool_error(result)
        Array(result['content']).filter_map { |c| c['text'] if c.is_a?(Hash) }.first.presence ||
          'Epidemic Sound MCP tool error'
      end

      # The endpoint answers either application/json (parsed to a Hash by Faraday)
      # or an SSE stream (left as a String) — handle both, then surface JSON-RPC
      # errors uniformly.
      def rpc_result(response)
        message = response.body.is_a?(Hash) ? response.body : parse_sse(response.body)
        return nil unless message.is_a?(Hash)

        if message['error'].is_a?(Hash)
          raise Error.new(message['error']['message'] || 'JSON-RPC error', body: message['error'])
        end

        message['result']
      end

      def parse_sse(body)
        body.to_s.each_line.filter_map do |line|
          next unless line.start_with?('data:')

          parsed = parse_maybe_json(line.delete_prefix('data:').strip)
          parsed if parsed.is_a?(Hash) && (parsed.key?('result') || parsed.key?('error'))
        end.last
      end

      def parse_maybe_json(text)
        return text unless text.is_a?(String) && text.strip.start_with?('{', '[')

        JSON.parse(text)
      rescue JSON::ParserError
        text
      end

      def raise_on_error!(response)
        return if response.success?

        klass =
          case response.status
          when 401, 403 then AuthenticationError
          when 429      then RateLimitError
          when 500..599 then ServerError
          else Error
          end
        raise klass.new("Epidemic Sound MCP (HTTP #{response.status})", status: response.status, body: response.body)
      end

      def connection
        @connection ||= build_connection(
          ENDPOINT,
          headers: {
            'Accept' => 'application/json, text/event-stream',
            'MCP-Protocol-Version' => PROTOCOL_VERSION
          },
          auth_token: @api_key
        )
      end
    end
  end
end
