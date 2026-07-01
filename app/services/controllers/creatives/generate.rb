# frozen_string_literal: true

module Controllers
  module Creatives
    # POST /tickets/:ticket_id/creatives/generate — body { kind, params }.
    # Routes the kind to the matching generation operation. Guests cannot generate.
    class Generate < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        require_billing!
        # Video + image consume prepaid credits (carousels are included). Fail
        # fast with 402 before creating any records.
        require_credits!(kind: @params[:kind])
        ticket = workspace.tickets.find(@params[:ticket_id])
        { generation: serialize(run(ticket), GenerationSerializer) }
      end

      private

      def run(ticket)
        gen_params = generation_params
        case @params[:kind].to_s
        when "carousel"
          Operations::Creatives::GenerateViralCarousel.call(
            ticket: ticket, slides: gen_params[:slides], params: gen_params
          )
        when "video"
          Operations::Creatives::GenerateUgcVideo.call(
            ticket: ticket, script: gen_params[:script],
            avatar: gen_params[:avatar], voice: gen_params[:voice],
            creative_type: @params[:type].presence
          )
        when "image"
          Operations::Creatives::GenerateImage.call(
            ticket: ticket, prompt: gen_params[:prompt],
            ref_images: gen_params.fetch(:ref_images, []),
            creative_type: @params[:type].presence
          )
        else
          raise Operations::Errors::Invalid, "Tipo de geração desconhecido: #{@params[:kind]}"
        end
      end

      def generation_params
        raw = @params[:params]
        return {} if raw.blank?

        raw.permit!.to_h.symbolize_keys
      end
    end
  end
end
