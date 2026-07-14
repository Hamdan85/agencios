# frozen_string_literal: true

module Creatives
  # Runs the slow half of a carousel generation (copy AI + image slots +
  # Chromium render) off the request — generations only START in-request;
  # results arrive via Action Cable. No retries: Operations::Creatives::RenderCarousel
  # already refunds and fails the generation on error, and a Sidekiq retry after
  # that refund would double-spend the wallet.
  class RenderCarouselJob < ApplicationJob
    queue_as :media

    discard_on StandardError

    def perform(generation_id)
      generation = Generation.find_by(id: generation_id)
      # Only render a still-pending generation (the reaper/cancel may have
      # already failed + refunded it).
      return unless generation&.status_processing?

      # Reused generation/AI ops read Current.workspace/user; set the tenant so
      # cost logging and any workspace-scoped read resolve correctly in the job.
      Current.workspace = generation.workspace
      Current.actor = generation.user
      Operations::Creatives::RenderCarousel.call(generation: generation)
    end
  end
end
