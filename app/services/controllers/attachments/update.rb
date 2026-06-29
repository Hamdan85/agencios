# frozen_string_literal: true

module Controllers
  module Attachments
    # Rename / describe / reorder a file. Guests cannot mutate.
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:ticket_id])
        attachment = ticket.attachments.find(@params[:id])
        Operations::Attachments::Update.call(attachment: attachment, attributes: attachment_params)
        { attachment: serialize(attachment.reload, AttachmentSerializer) }
      end

      private

      def attachment_params
        @params.fetch(:attachment, {}).permit(:title, :description, :position).to_h
      end
    end
  end
end
