# frozen_string_literal: true

module Controllers
  module Attachments
    # Upload one or more files to a ticket. Accepts a single `file` or a `files`
    # array (multi-select / drag-and-drop) — one Attachment is created per file.
    # Guests (read-only client view) cannot upload.
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:ticket_id])
        files = uploaded_files
        raise Operations::Errors::Invalid, 'Nenhum arquivo enviado.' if files.empty?

        created = files.map { |file| create_one(ticket, file) }
        { attachments: serialize_collection(created, AttachmentSerializer) }
      end

      private

      def create_one(ticket, file)
        Operations::Attachments::Create.call(
          ticket: ticket,
          file: file,
          uploaded_by: user,
          # title/description only apply to a single-file upload.
          title: single? ? @params[:title] : nil,
          description: single? ? @params[:description] : nil
        )
      end

      def uploaded_files
        [@params[:files], @params[:file]].flatten.compact
      end

      def single?
        uploaded_files.size == 1
      end
    end
  end
end
