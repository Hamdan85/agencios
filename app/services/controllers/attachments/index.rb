# frozen_string_literal: true

module Controllers
  module Attachments
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:ticket_id])
        { attachments: serialize_collection(ticket.attachments.ordered, AttachmentSerializer) }
      end
    end
  end
end
