# frozen_string_literal: true

module Creatives
  # Runs the slow half of an image generation (the vendor render) off the
  # request — generations only START in-request; results arrive via Action
  # Cable. No retries: Operations::Creatives::RenderImage already refunds and
  # fails the generation on error, and a Sidekiq retry after that refund would
  # double-spend the wallet.
  class RenderImageJob < ApplicationJob
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
      Operations::Creatives::RenderImage.call(generation: generation)
    end
  end
end
