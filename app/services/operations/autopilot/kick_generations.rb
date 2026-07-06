# frozen_string_literal: true

module Operations
  module Autopilot
    # Phase 2: generate EVERY scoped creative for the ticket. Reuses the studio
    # generation ops (which already fold the ticket's brand/scope context into the
    # prompt) — image + carousel finish inline, video is async. Records the
    # generation ids, then either parks in `awaiting_generation` (a video is still
    # rendering) or advances straight to `publishing` (all sync).
    #
    # The per-generation credit debit happens inside each generate op; the
    # controller pre-checked the whole run, so this normally cannot overspend — a
    # concurrent spend that races is caught by Advance and halts the run.
    class KickGenerations < Operations::Base
      def initialize(run:)
        @run = run
        @ticket = run.ticket
      end

      def call
        return unless claim!

        generations = kick_all
        ids = generations.map(&:id)
        creative_ids = generations.filter_map(&:creative_id).map(&:to_s)
        pending = generations.any? { |g| g.status_queued? || g.status_processing? }

        @run.update!(
          state: 'awaiting_generation',
          progress: @run.progress.merge(
            'generation_ids' => ids, 'creative_ids' => creative_ids, 'total_creatives' => ids.size
          )
        )
        Broadcaster.ticket(@ticket, 'autopilot_progress',
                           run_id: @run.id, state: @run.state, total: ids.size)

        if pending
          AutopilotWatchdogJob.set(wait: AutopilotWatchdogJob::TIMEOUT).perform_later(@run.id)
        else
          # All creatives are ready synchronously — GO stops at production.
          Operations::Autopilot::Complete.call(run: @run)
        end
      end

      private

      # Claim the run out of `generating` exactly once — the `kicked` flag makes a
      # duplicate delivery skip re-generating (and re-charging) the creatives.
      def claim!
        @run.with_lock do
          next false unless @run.state == 'generating' && !@run.progress['kicked']

          @run.update!(progress: @run.progress.merge('kicked' => true))
          true
        end
      end

      def kick_all
        @ticket.creative_types_list.filter_map do |type|
          spec = ::Creatives.spec_for(type)
          next unless spec && spec[:generatable]

          generate(spec[:kind], type)
        end
      end

      def generate(kind, type)
        case kind
        when 'carousel'
          Operations::Creatives::GenerateViralCarousel.call(ticket: @ticket, params: { client_id: client_id })
        when 'video'
          Operations::Creatives::GenerateUgcVideo.call(ticket: @ticket, creative_type: type, client_id: client_id)
        when 'image'
          Operations::Creatives::GenerateImage.call(ticket: @ticket, creative_type: type, client_id: client_id)
        end
      end

      def client_id = @ticket.project&.client_id
    end
  end
end
