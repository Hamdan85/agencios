# frozen_string_literal: true

module Controllers
  module Clients
    # POST /clients/:id/reanalyze_carousel_palette — re-derive the image-style
    # carousel palette from the client's current background photo (force: true, so
    # it re-rolls even for the same image). Async; the client is refetched by the
    # frontend once the job lands the new palette. Manager-gated.
    class ReanalyzeCarouselPalette < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        client = workspace.clients.find(@params[:id])
        unless client.carousel_background.attached?
          raise Operations::Errors::Invalid, 'Defina uma imagem de fundo antes de analisar as cores.'
        end

        Creatives::DeriveCarouselPaletteJob.perform_later(client.id, force: true)
        { client: serialize(client, ClientSerializer) }
      end
    end
  end
end
