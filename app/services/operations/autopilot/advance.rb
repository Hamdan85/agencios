# frozen_string_literal: true

module Operations
  module Autopilot
    # The autopilot "tick": the single entry point that drives a ticket-run one
    # phase forward. Re-invoked by AutopilotAdvanceJob (synchronous phases), by
    # OnGenerationSettled (async video finished), and by the watchdog. Idempotent
    # and re-entrant — each phase op claims its state under a row lock, so a
    # duplicate delivery no-ops.
    #
    # Any unexpected error (or a mid-run credit shortfall) halts the run via Fail
    # rather than looping — a run must never spin forever.
    class Advance < Operations::Base
      def initialize(run:)
        @run = run
      end

      def call
        return @run if @run.terminal?

        case @run.state
        when 'pending'             then WalkToProduction.call(run: @run)
        when 'generating'          then KickGenerations.call(run: @run)
        when 'awaiting_generation' then OnGenerationSettled.reconcile(run: @run)
        end
        @run
      rescue Operations::Errors::InsufficientCredits => e
        shortfall = e.required.to_i - e.available.to_i
        reason = I18n.with_locale(workspace_locale(@run.workspace)) do
          I18n.t('operations.autopilot.reason.insufficient_credits', shortfall: shortfall)
        end
        Fail.call(run: @run, reason: reason)
      rescue StandardError => e
        Rails.logger.error("[Autopilot::Advance] run #{@run.id} (#{@run.state}) failed: #{e.message}")
        Fail.call(run: @run, reason: e.message.to_s.truncate(480))
      end

      private

      def workspace_locale(ws)
        I18n.available_locales.find { |l| l.to_s == ws&.locale.to_s } || I18n.default_locale
      end
    end
  end
end
