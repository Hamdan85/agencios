# frozen_string_literal: true

module Vendors
  module Anthropic
    # Anthropic Messages API client (https://api.anthropic.com/v1/messages).
    #
    # When an API key is configured (`anthropic.api_key` credential, or the
    # `ANTHROPIC_API_KEY` env var) it makes a real call and returns the assistant
    # text. When the key is ABSENT it returns a deterministic offline stub so the
    # AI pipeline (ticket summaries, captions, scope, retrospectives) keeps working
    # in development without credentials.
    #
    # See docs: the Messages API takes `{ model, max_tokens, system, messages }`
    # and the assistant text is at `content[0].text`.
    class Client < Vendors::Base
      BASE_URL = "https://api.anthropic.com"
      API_VERSION = "2023-06-01"
      # Latest Sonnet generation; override via `anthropic.model` / ANTHROPIC_MODEL.
      DEFAULT_MODEL = "claude-3-5-sonnet-latest"

      def initialize(api_key: nil, model: nil)
        @api_key = api_key || credential(:anthropic, :api_key, env: "ANTHROPIC_API_KEY")
        @model   = model || credential(:anthropic, :model, env: "ANTHROPIC_MODEL") || DEFAULT_MODEL
      end

      # Returns the assistant text as a plain String.
      def messages(system:, prompt:, max_tokens: 1024)
        return stub(system: system, prompt: prompt) if @api_key.blank?

        body = handle(connection.post("/v1/messages", {
          model: @model,
          max_tokens: max_tokens,
          system: system,
          messages: [{ role: "user", content: prompt.to_s }]
        }))

        extract_text(body)
      rescue Vendors::Base::Error => e
        # Never let an AI outage break a status transition or caption job; fall
        # back to the deterministic stub and log.
        Rails.logger.warn("[Vendors::Anthropic] #{e.class}: #{e.message} — returning stub.")
        stub(system: system, prompt: prompt)
      end

      private

      def connection
        @connection ||= build_connection(
          BASE_URL,
          headers: {
            "x-api-key" => @api_key.to_s,
            "anthropic-version" => API_VERSION,
            "Content-Type" => "application/json"
          }
        )
      end

      # The Messages API returns `content` as an array of blocks; concatenate the
      # text of every `type: "text"` block.
      def extract_text(body)
        content = body.is_a?(Hash) ? body["content"] : nil
        return body.to_s unless content.is_a?(Array)

        content
          .select { |block| block.is_a?(Hash) && block["type"] == "text" }
          .map { |block| block["text"] }
          .join("\n")
          .presence || ""
      end

      # Deterministic, offline placeholder echoing the head of the prompt.
      def stub(system:, prompt:)
        excerpt = prompt.to_s.strip[0, 200]
        "[stub] #{excerpt}".strip
      end
    end
  end
end
