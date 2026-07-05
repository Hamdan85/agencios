# frozen_string_literal: true

module Vendors
  # Cartesia — a low-latency TTS with a FIXED voice per `voice_id`. We synthesize
  # each scene's spoken line with the SAME voice_id so the voice is identical
  # across every clip of a video (the model's own per-clip voice drifts). The
  # audio then drives the render (lip-sync reference) and/or is dubbed in post.
  #
  # App-level `api_key` in credentials (`cartesia.api_key`), ENV fallback.
  # Docs: https://docs.cartesia.ai (TTS bytes endpoint). Exact request fields are
  # confirmed against the docs at integration time.
  module Cartesia
    class Client < Vendors::Base
      BASE_URL = 'https://api.cartesia.ai'
      # A dated API version header Cartesia requires on every request.
      API_VERSION = '2024-11-13'
      DEFAULT_MODEL = 'sonic-2'

      def initialize(api_key: nil)
        @api_key = api_key || credential(:cartesia, :api_key, env: 'CARTESIA_API_KEY')
      end

      def configured? = @api_key.present?

      # Synthesize speech for `text` in the fixed `voice_id`. Returns the raw
      # audio bytes + content type: { bytes:, content_type: }. Raises on error /
      # missing key (the never-raise wrapper is Actions::Synthesize).
      #   language: BCP-47 (pt for Brazilian Portuguese)
      #   speed:    optional pacing hint ('slow' | 'normal' | 'fast')
      def synthesize(text:, voice_id:, language: 'pt', speed: nil, model: DEFAULT_MODEL)
        require_credential!(@api_key, 'cartesia.api_key')

        payload = {
          model_id: model,
          transcript: text.to_s,
          voice: { mode: 'id', id: voice_id.to_s },
          language: language,
          output_format: { container: 'mp3', sample_rate: 44_100, bit_rate: 128_000 }
        }
        payload[:speed] = speed if speed.present?

        # `/tts/bytes` returns raw audio (not JSON) — the base JSON response
        # middleware only parses application/json, so `handle` returns the bytes
        # untouched; an error body (JSON) still maps to a proper error.
        body = handle(connection.post('/tts/bytes') { |req| req.body = payload })
        { bytes: body.to_s.dup.force_encoding(Encoding::BINARY), content_type: 'audio/mpeg' }
      end

      # The voice LIBRARY (so the orchestrator can pick the best-fitting voice for
      # a character instead of a hand-curated catalog). The `/voices` list is
      # PAGINATED (cursor `next_page` / `has_more`) and language-mixed, so we page
      # through it, filter to `language` (nil = all), and put Brazilian voices
      # first (for PT-BR content). Returns
      # [{ id:, name:, description:, language:, gender:, country: }].
      def voices(language: VideoConfig::VOICE_LANGUAGE, limit: 100, max_pages: 12)
        require_credential!(@api_key, 'cartesia.api_key')

        all = []
        cursor = nil
        max_pages.times do
          params = { limit: limit }
          params[:starting_after] = cursor if cursor.present?
          body = handle(connection.get('/voices', params))
          all.concat(body.is_a?(Hash) ? Array(body['data'] || body['voices']) : Array(body))
          cursor = body.is_a?(Hash) ? body['next_page'] : nil
          break unless body.is_a?(Hash) && body['has_more'] && cursor.present?
        end

        list = all.filter_map { |v| normalize_voice(v) }
        list = list.select { |v| v[:language].to_s.downcase.start_with?(language.to_s.downcase) } if language.present?
        list.sort_by { |v| v[:country].to_s.upcase == 'BR' ? 0 : 1 } # BR first for PT-BR
      end

      private

      def normalize_voice(voice)
        h = voice.is_a?(Hash) ? voice : {}
        id = (h['id'] || h['voice_id']).to_s
        return nil if id.blank?

        { id: id, name: h['name'].to_s.strip, description: h['description'].to_s.strip,
          language: (h['language'] || h.dig('metadata', 'language')).to_s, gender: h['gender'].to_s,
          country: h['country'].to_s }
      end

      def connection
        @connection ||= build_connection(
          BASE_URL, headers: { 'X-API-Key' => @api_key.to_s, 'Cartesia-Version' => API_VERSION }
        )
      end
    end
  end
end
