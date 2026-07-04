# frozen_string_literal: true

module Operations
  module Generations
    # Studio dispatcher: routes a generation request (by kind) to the right
    # creative-generation operation. The ticket is optional — the studio can
    # generate standalone creatives. Returns the Generation.
    class Run < Operations::Base
      def initialize(workspace:, user:, kind:, params: {})
        @workspace = workspace
        @user = user
        @kind = kind.to_s
        @params = (params || {}).to_h.symbolize_keys
      end

      def call
        case @kind
        when 'carousel'
          Operations::Creatives::GenerateViralCarousel.call(
            ticket: ticket,
            slides: @params[:slides],
            params: @params
          )
        when 'video'
          Operations::Creatives::GenerateUgcVideo.call(
            ticket: ticket,
            mode: @params[:mode],
            script: @params[:script],
            prompt: @params[:prompt],
            avatar: @params[:avatar],
            voice: @params[:voice],
            aspect_ratio: @params[:aspect_ratio],
            duration: @params[:duration],
            reference_image_urls: @params.fetch(:reference_image_urls, []),
            with_audio: @params.fetch(:with_audio, true),
            client_id: @params[:client_id]
          )
        when 'image'
          Operations::Creatives::GenerateImage.call(
            ticket: ticket,
            prompt: @params[:prompt],
            ref_images: @params.fetch(:ref_images, []),
            client_id: @params[:client_id]
          )
        else
          raise Operations::Errors::Invalid, "Tipo de geração desconhecido: #{@kind}"
        end
      end

      private

      # Resolve an optional ticket, scoped to the active workspace.
      def ticket
        return @ticket if defined?(@ticket)

        ticket_id = @params[:ticket_id]
        @ticket = ticket_id.present? ? @workspace.tickets.find(ticket_id) : nil
      end
    end
  end
end
