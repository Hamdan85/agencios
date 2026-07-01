# frozen_string_literal: true

# Safety net for runs parked in `awaiting_generation`: if both the HeyGen webhook
# AND PollHeygenVideoJob somehow fail to re-enter the engine (e.g. an exception in
# OnGenerationSettled, or a lost race), this re-derives the run from its Generation
# rows and either advances it or halts it. Scheduled once when a run parks.
class AutopilotWatchdogJob < ApplicationJob
  queue_as :low

  # Comfortably past the HeyGen poll ceiling (MAX_ATTEMPTS × backoff ≈ a few
  # minutes) so we only step in after the normal paths have had their chance.
  TIMEOUT = 12.minutes

  def perform(run_id)
    run = AutopilotRun.find_by(id: run_id)
    return unless run
    return unless run.state == 'awaiting_generation'

    Current.workspace = run.workspace
    Current.actor = run.user

    gens = Generation.where(id: run.generation_ids).to_a
    still_pending = gens.select { |g| g.status_queued? || g.status_processing? }

    if still_pending.any?
      # Renders genuinely still running — the vendor poll owns them; check back.
      self.class.set(wait: TIMEOUT).perform_later(run_id)
    else
      Operations::Autopilot::OnGenerationSettled.reconcile(run: run)
    end
  ensure
    Current.reset
  end
end
