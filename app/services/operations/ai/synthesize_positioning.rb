# frozen_string_literal: true

module Operations
  module Ai
    # AI-first positioning: takes the client's free-text brand description and
    # returns the FULL structured positioning bag (the model fills the fields).
    # Stateless on purpose — the wizard calls this BEFORE the client exists.
    #
    # Returns a sanitized positioning Hash (Client::POSITIONING_KEYS only). Parsing
    # is defensive: when the model output isn't valid JSON (e.g. the offline
    # Anthropic stub), it degrades to seeding `one_liner` with the brief so the
    # wizard still has something to show.
    class SynthesizePositioning < Operations::Base
      def initialize(brief:, name: nil)
        @brief = brief.to_s
        @name = name
      end

      def call
        builder = Prompts::ClientPositioning.new(brief: @brief, name: @name)
        text = AiAdapter.complete(builder, max_tokens: 900, operation: "synthesize_positioning").to_s

        parsed = parse(text)
        Client.sanitize_positioning(parsed.presence || fallback)
      rescue StandardError => e
        # The wizard calls this synchronously — never hard-fail it. Degrade to the
        # brief so the user still has something to edit.
        Rails.logger.warn("[Ai::SynthesizePositioning] #{e.class}: #{e.message}")
        Client.sanitize_positioning(fallback)
      end

      private

      def parse(text)
        raw = text[/\{.*\}/m]
        return {} unless raw

        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end

      def fallback
        return {} if @brief.blank?

        { "one_liner" => @brief.strip[0, 280] }
      end
    end
  end
end
