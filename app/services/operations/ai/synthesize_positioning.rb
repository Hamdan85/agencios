# frozen_string_literal: true

module Operations
  module Ai
    # Synthesizes a brand positioning statement (+ suggested content pillars) from
    # the wizard inputs. Stateless on purpose: the wizard calls this BEFORE the
    # client exists, so it takes a raw inputs hash rather than a Client.
    #
    # Returns { statement: String, content_pillars: [String] }. Parsing is
    # defensive: if the model output lacks the expected markers (e.g. the offline
    # Anthropic stub), the whole text becomes the statement and pillars stay empty.
    class SynthesizePositioning < Operations::Base
      def initialize(inputs:, name: nil)
        @inputs = inputs.to_h
        @name = name
      end

      def call
        builder = Prompts::ClientPositioning.new(inputs: @inputs, name: @name)
        text = AiAdapter.complete(builder, max_tokens: 700).to_s.strip

        { statement: extract_statement(text), content_pillars: extract_pillars(text) }
      end

      private

      def extract_statement(text)
        section = text[/POSICIONAMENTO:\s*(.+?)(?:\n\s*PILARES:|\z)/mi, 1]
        (section || text).strip
      end

      def extract_pillars(text)
        block = text[/PILARES:\s*(.+)\z/mi, 1]
        return [] if block.blank?

        block.lines.filter_map do |line|
          pillar = line.strip.sub(/\A[-*\d.]+\s*/, "").strip
          pillar.presence
        end.first(5)
      end
    end
  end
end
