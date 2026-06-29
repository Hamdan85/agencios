# frozen_string_literal: true

module Controllers
  module Attachments
    # Remove a file. Allowed for managers (any file) or the original uploader.
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:ticket_id])
        attachment = ticket.attachments.find(@params[:id])
        authorize_removal!(attachment)
        Operations::Attachments::Destroy.call(attachment: attachment)
        { message: "Arquivo removido." }
      end

      private

      def authorize_removal!(attachment)
        return if membership&.can_manage?
        return if attachment.uploaded_by_id == user&.id

        raise Operations::Errors::Forbidden, "Apenas quem enviou o arquivo ou um gestor pode removê-lo."
      end
    end
  end
end
