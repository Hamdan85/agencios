# frozen_string_literal: true

# Runs the slow half of a video generation (AI storyboard + first scene submit)
# off the request. No retries: Operations::Video::StartRender already refunds and
# fails the generation on error, and a Sidekiq retry after that refund would
# double-spend the wallet.
class StartVideoRenderJob < ApplicationJob
  queue_as :media

  discard_on StandardError

  def perform(generation_id)
    generation = Generation.find_by(id: generation_id)
    return unless generation

    Operations::Video::StartRender.call(generation: generation)
  end
end
