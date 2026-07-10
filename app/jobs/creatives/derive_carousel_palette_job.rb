# frozen_string_literal: true

module Creatives
  # Runs the vision-based carousel-palette derivation off the request path (the
  # image can be several MB and the vision call adds latency, so the brand-asset
  # upload returns immediately). Enqueued whenever a client's carousel background
  # is set/changed or the style flips to `image`, plus manual re-analyze.
  class DeriveCarouselPaletteJob < ApplicationJob
    queue_as :media

    def perform(client_id, force: false)
      client = Client.find_by(id: client_id)
      return unless client

      # Reused generation/AI ops read Current.workspace/user; set the tenant so
      # cost logging and any workspace-scoped read resolve correctly in the job.
      Current.workspace = client.workspace
      Operations::Creatives::DeriveCarouselPalette.call(client: client, force: force)
    end
  end
end
