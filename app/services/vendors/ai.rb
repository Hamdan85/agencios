# frozen_string_literal: true

module Vendors
  # Provider seam for the text-AI layer. Every AI call site instantiates its
  # client through `Vendors::Ai.client` instead of a concrete vendor, so the
  # platform can run on OpenRouter (many models, real per-call cost) or Anthropic
  # (direct) by flipping one credential — with both coexisting for canary/rollback.
  #
  # The two clients share the exact same public surface (#messages, #generate,
  # #stream) and return these shared result structs, so callers (AiAdapter,
  # Operations::Strategy::Converse, specs) never branch on the provider.
  module Ai
    # Assistant text + token/cost `usage` hash + resolved model. `tool_input` is
    # the captured forced-tool input (Hash) when a `tool:` was passed — else nil.
    Result = Struct.new(:text, :usage, :model, :tool_input, keyword_init: true)

    # Streaming result: full text, every captured tool call ([{ name:, input: }]),
    # `usage`, and the model.
    StreamResult = Struct.new(:text, :tools, :usage, :model, keyword_init: true)

    module_function

    # The configured client. `model:` (optional) overrides the provider default —
    # used for per-operation routing (see `.model_for`).
    def client(api_key: nil, model: nil)
      if provider == AiUsageLog::PROVIDER_ANTHROPIC
        Vendors::Anthropic::Client.new(api_key: api_key, model: model)
      else
        Vendors::OpenRouter::Client.new(api_key: api_key, model: model)
      end
    end

    # Provider decision, in order: the admin-editable AiConfig (no deploy), then
    # the `ai_provider` credential / AI_PROVIDER env, then auto-detect (OpenRouter
    # once its key is configured, else the direct Anthropic key — safe rollout).
    def provider
      explicit = (AiConfig.instance.resolved_provider.presence ||
                  Rails.application.credentials.ai_provider ||
                  ENV['AI_PROVIDER']).to_s.strip.downcase
      return explicit if explicit.present?
      return AiUsageLog::PROVIDER_OPENROUTER if openrouter_key?

      AiUsageLog::PROVIDER_ANTHROPIC
    end

    # Per-operation model (OpenRouter only): the admin-editable AiConfig routing
    # (per-operation override, else its default model), falling back to the
    # `openrouter.models` credential map. nil → the client's own default.
    def model_for(operation)
      return nil unless provider == AiUsageLog::PROVIDER_OPENROUTER

      AiConfig.instance.model_for(operation).presence || credential_model_for(operation)
    end

    def credential_model_for(operation)
      map = Rails.application.credentials.dig(:openrouter, :models)
      return nil unless map.is_a?(Hash)

      (map[operation.to_s] || map[operation.to_sym]).to_s.presence
    end

    def openrouter_key?
      (Rails.application.credentials.dig(:openrouter, :api_key) || ENV['OPENROUTER_API_KEY']).present?
    end
  end
end
