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
    # Supports the server-side `web_fetch` tool: with `web_fetch: true`, Claude
    # itself reads any URL present in the prompt and uses it as context (used by
    # the carousel generator for the "link" source).
    class Client < Vendors::Base
      BASE_URL    = "https://api.anthropic.com"
      API_VERSION = "2023-06-01"
      # Current Sonnet — supports the web_fetch tool. Override via
      # `anthropic.model` / ANTHROPIC_MODEL.
      DEFAULT_MODEL = "claude-sonnet-4-6"
      # web_fetch requires a current model (4.6+). Override via
      # `anthropic.fetch_model` / ANTHROPIC_FETCH_MODEL.
      DEFAULT_FETCH_MODEL = "claude-sonnet-4-6"

      WEB_FETCH_TOOL    = { "type" => "web_fetch_20260209", "name" => "web_fetch", "max_uses" => 5 }.freeze
      WEB_FETCH_BETA    = "web-fetch-2025-09-10"
      MAX_TOOL_CONTINUE = 5

      attr_reader :model

      # Carries the assistant text alongside the token `usage` hash and the
      # resolved model id, so callers can record AI cost (AiUsageLog).
      Result = Struct.new(:text, :usage, :model, keyword_init: true)

      def initialize(api_key: nil, model: nil)
        @api_key = api_key || credential(:anthropic, :api_key, env: "ANTHROPIC_API_KEY")
        @model   = model || credential(:anthropic, :model, env: "ANTHROPIC_MODEL").presence || DEFAULT_MODEL
      end

      # Returns the assistant text as a plain String.
      def messages(system:, prompt:, max_tokens: 1024)
        generate(system: system, prompt: prompt, max_tokens: max_tokens).text
      end

      # Like #messages but returns a Result { text, usage, model } so the caller
      # can record token cost. The offline stub returns empty usage (cost 0).
      #
      # web_fetch: true enables the server-side web_fetch tool (Claude reads URLs
      # in the prompt itself) and uses a fetch-capable model.
      def generate(system:, prompt:, max_tokens: 1024, web_fetch: false)
        target = web_fetch ? fetch_model : @model
        return Result.new(text: stub(system: system, prompt: prompt), usage: {}, model: target) if @api_key.blank?

        messages = [{ role: "user", content: prompt.to_s }]
        body  = request(model: target, system: system, messages: messages, max_tokens: max_tokens, web_fetch: web_fetch)
        usage = usage_acc(body)

        # Server-tool loops can pause (pause_turn); resume by re-sending.
        guard = 0
        while body.is_a?(Hash) && body["stop_reason"] == "pause_turn" && guard < MAX_TOOL_CONTINUE
          messages << { role: "assistant", content: body["content"] }
          body = request(model: target, system: system, messages: messages, max_tokens: max_tokens, web_fetch: web_fetch)
          usage = usage_acc(body, into: usage)
          guard += 1
        end

        Result.new(
          text:  extract_text(body),
          usage: usage,
          model: (body.is_a?(Hash) && body["model"].presence) || target
        )
      rescue Vendors::Base::Error, Faraday::Error => e
        # Never let an AI outage (incl. timeouts) break a status transition, a
        # caption job, or a generation; fall back to the deterministic stub.
        Rails.logger.warn("[Vendors::Anthropic] #{e.class}: #{e.message} — returning stub.")
        Result.new(text: stub(system: system, prompt: prompt), usage: {}, model: target)
      end

      private

      def request(model:, system:, messages:, max_tokens:, web_fetch:)
        payload = { model: model, max_tokens: max_tokens, system: system, messages: messages }
        payload[:tools] = [WEB_FETCH_TOOL] if web_fetch

        handle(connection.post("/v1/messages") do |req|
          req.body = payload
          req.headers["anthropic-beta"] = WEB_FETCH_BETA if web_fetch
        end)
      end

      def fetch_model
        credential(:anthropic, :fetch_model, env: "ANTHROPIC_FETCH_MODEL").presence || DEFAULT_FETCH_MODEL
      end

      # Accumulate token usage across (possibly multiple) turns.
      def usage_acc(body, into: nil)
        usage = body.is_a?(Hash) && body["usage"].is_a?(Hash) ? body["usage"] : {}
        return usage if into.nil?

        %w[input_tokens output_tokens cache_creation_input_tokens cache_read_input_tokens].each_with_object(into.dup) do |k, acc|
          acc[k] = acc[k].to_i + usage[k].to_i
        end
      end

      def connection
        @connection ||= build_connection(
          BASE_URL,
          headers: {
            "x-api-key" => @api_key.to_s,
            "anthropic-version" => API_VERSION,
            "Content-Type" => "application/json"
          }
        ).tap do |conn|
          # web_fetch reads full pages then writes the carousel — well past the
          # 30s default. Give the model room so it never times out mid-generation.
          conn.options.timeout = 180
          conn.options.open_timeout = 10
        end
      end

      # The Messages API returns `content` as an array of blocks; concatenate the
      # text of every `type: "text"` block (tool-use/result blocks are skipped).
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
