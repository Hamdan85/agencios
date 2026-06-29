# frozen_string_literal: true

# Safety-net poller for HeyGen renders. The webhook (`avatar_video.success`) is
# the fast path; this job is the fallback for missed/late webhooks.
#
# It calls `Vendors::Heygen::Actions::GetVideoStatus` for the Generation's
# `external_id` (the HeyGen video_id). When `completed`, it hands off to
# `Operations::Creatives::FinalizeGeneration` (download → attach → meter →
# broadcast). When still rendering, it re-enqueues with linear backoff up to a
# cap. When `failed`, it marks the Generation + Creative failed.
class PollHeygenVideoJob < ApplicationJob
  queue_as :media

  MAX_ATTEMPTS = 20
  BACKOFF_STEP = 15.seconds

  def perform(generation_id, attempt = 1)
    generation = Generation.find_by(id: generation_id)
    return unless generation
    return if generation.status_completed? || generation.status_failed?
    return if generation.external_id.blank?

    status = Vendors::Heygen::Actions::GetVideoStatus.call(video_id: generation.external_id)

    if status[:completed]
      Operations::Creatives::FinalizeGeneration.call(
        generation: generation,
        video_url: status[:video_url],
        duration: status[:duration],
        metadata: {
          thumbnail_url: status[:thumbnail_url],
          gif_url: status[:gif_url],
          duration: status[:duration]
        }.compact
      )
    elsif status[:failed]
      mark_failed(generation, status[:failure_message])
    elsif attempt < MAX_ATTEMPTS
      self.class.set(wait: BACKOFF_STEP * attempt).perform_later(generation_id, attempt + 1)
    else
      mark_failed(generation, "Render timed out after #{MAX_ATTEMPTS} polls")
    end
  end

  private

  def mark_failed(generation, reason)
    generation.update!(status: :failed, failure_reason: reason.to_s.presence)
    generation.creative&.update!(status: :failed)

    if generation.creative&.ticket
      Broadcaster.ticket(generation.creative.ticket, "creative_failed", creative_id: generation.creative.id)
    end
    Broadcaster.generations(generation.workspace_id, "generation_failed", id: generation.id, kind: generation.kind)
  end
end
