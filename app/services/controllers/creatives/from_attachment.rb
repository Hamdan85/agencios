# frozen_string_literal: true

module Controllers
  module Creatives
    # POST /tickets/:ticket_id/creatives/from_attachment — turn a file already
    # uploaded to this ticket into a creative (body: { attachment_id,
    # creative_type, caption? }). No re-upload: the asset shares the blob.
    class FromAttachment < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:ticket_id])
        attachment = ticket.attachments.find(@params.require(:attachment_id))

        creative = Operations::Creatives::CreateFromAttachment.call(
          ticket: ticket,
          attachment: attachment,
          creative_type: @params.require(:creative_type),
          caption: @params[:caption]
        )
        { creative: serialize(creative, CreativeSerializer) }
      end
    end
  end
end
