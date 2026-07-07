# frozen_string_literal: true

module Operations
  module Ai
    # The single, never-raising entry point for the AI cost ledger (AiUsageLog).
    #
    # Records one AI vendor call so total spend can be broken down per
    # provider/operation/model/subject. A logging failure must NEVER break the AI
    # call that already succeeded — every error is swallowed and logged.
    #
    # Token shape (Anthropic/OpenRouter): pass `usage:` (the Messages API `usage`
    # hash) and `model:`. Unit shape (Banana/Cartesia): pass `units:` +
    # `unit_kind:`, or an explicit `cost_cents:` when the real cost is known.
    #
    # Runs both inside requests (resolves tenant from Current) and out of them
    # (jobs/webhooks pass `workspace:`/`user:`/`subject:` explicitly).
    class LogUsage < Operations::Base
      def initialize(provider:, operation:, model: nil, usage: nil,
                     units: nil, unit_kind: nil, cost_cents: nil,
                     subject: nil, workspace: nil, user: nil)
        @provider   = provider.to_s
        @operation  = operation.to_s
        @model      = model
        @usage      = usage || {}
        @units      = units
        @unit_kind  = unit_kind
        @cost_cents = cost_cents
        @subject    = subject
        @workspace  = workspace
        @user       = user
      end

      def call
        ws = resolve_workspace
        return nil if ws.nil?

        AiUsageLog.create!(
          workspace: ws,
          user: resolve_user,
          subject: @subject,
          provider: @provider,
          operation: @operation,
          model: @model.to_s.presence,
          input_tokens: token(:input_tokens),
          output_tokens: token(:output_tokens),
          cache_creation_input_tokens: token(:cache_creation_input_tokens),
          cache_read_input_tokens: token(:cache_read_input_tokens),
          unit_kind: resolved_unit_kind,
          units: resolved_units,
          cost_cents: computed_cost_cents
        )
      rescue StandardError => e
        Rails.logger.warn("[Operations::Ai::LogUsage] failed (#{@provider}/#{@operation}): #{e.class}: #{e.message}")
        nil
      end

      private

      def resolve_workspace
        @workspace || subject_workspace || Current.workspace
      end

      def subject_workspace
        @subject.respond_to?(:workspace) ? @subject.workspace : nil
      rescue StandardError
        nil
      end

      def resolve_user
        @user || Current.user
      end

      # Anthropic usage hash uses string OR symbol keys depending on caller.
      def token(key)
        (@usage[key.to_s] || @usage[key.to_sym]).to_i
      end

      def batch?
        @operation.end_with?('_batch')
      end

      def resolved_unit_kind
        return @unit_kind.to_s if @unit_kind.present?
        return AiUsageLog::UNIT_TOKEN if token_provider?

        AiUsageLog::UNIT_PRICING.dig(@provider, :unit_kind)
      end

      def resolved_units
        @units || 0
      end

      def token_provider?
        AiUsageLog::TOKEN_PROVIDERS.include?(@provider)
      end

      def computed_cost_cents
        # OpenRouter reports the real USD cost per call; callers pass it as
        # `cost_cents` so we store it directly (no per-model price table).
        return @cost_cents if @cost_cents

        if @provider == AiUsageLog::PROVIDER_ANTHROPIC
          AiUsageLog.token_cost_cents(
            model: @model,
            input: token(:input_tokens),
            output: token(:output_tokens),
            cache_write: token(:cache_creation_input_tokens),
            cache_read: token(:cache_read_input_tokens),
            batch: batch?
          )
        elsif @units
          AiUsageLog.unit_cost_cents(provider: @provider, units: @units)
        else
          0.0
        end
      end
    end
  end
end
