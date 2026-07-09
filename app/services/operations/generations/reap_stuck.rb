# frozen_string_literal: true

module Operations
  module Generations
    # Safety net for generations/creatives stranded mid-flight in a non-terminal
    # state — a vendor outage or credit exhaustion (OpenRouter/Banana) that killed
    # the request, a Puma timeout on a synchronous studio generation, a killed
    # Sidekiq worker, an OOM, or a deploy restart. Without this they spin "Gerando…"
    # forever. Runs on a cron (see config/schedule.yml).
    #
    # Thresholds are kind-aware: image + carousel are synchronous (they finish in
    # seconds), so a few minutes stuck already means dead. Video renders async and
    # legitimately takes long — its own per-scene poll timeout normally fails it
    # first, so the reaper only catches truly dead runs well past any real render.
    class ReapStuck < Operations::Base
      SYNC_STUCK_AFTER  = 15.minutes # image + carousel (synchronous)
      VIDEO_STUCK_AFTER = 3.hours    # video (async; wide margin past any real render)

      def initialize(now: Time.current)
        @now = now
      end

      def call
        reaped  = reap_generations(%i[image carousel], @now - SYNC_STUCK_AFTER)
        reaped += reap_generations(%i[video], @now - VIDEO_STUCK_AFTER)
        reaped += reap_orphan_creatives(@now - SYNC_STUCK_AFTER)
        Rails.logger.info("[Generations::ReapStuck] failed #{reaped} stranded generation(s)/creative(s)") if reaped.positive?
        reaped
      end

      private

      # Generations still queued/processing past the cutoff → fail them. FailGeneration
      # refunds any held credits, fails the linked creative, broadcasts, and halts an
      # owning autopilot run — and is idempotent, so a race with a late callback is safe.
      def reap_generations(kinds, cutoff)
        Generation.where(kind: kinds, status: %i[queued processing])
                  .where(updated_at: ..cutoff)
                  .find_each.sum do |generation|
          Operations::Creatives::FailGeneration.call(
            generation: generation,
            reason: 'Geração expirada — o provedor não respondeu a tempo.'
          )
          1
        end
      end

      # Creatives left `generating` that never got a Generation row — a carousel/image
      # op that died between creating the creative and persisting its generation.
      # FailGeneration can't help (no generation), so fail the creative directly.
      def reap_orphan_creatives(cutoff)
        Creative.status_generating
                .where(updated_at: ..cutoff)
                .where.missing(:generation)
                .find_each.sum do |creative|
          creative.update!(status: :failed)
          broadcast_creative(creative)
          1
        end
      end

      def broadcast_creative(creative)
        Broadcaster.ticket(creative.ticket, 'creative_failed', creative_id: creative.id) if creative.ticket
      rescue StandardError
        nil
      end
    end
  end
end
