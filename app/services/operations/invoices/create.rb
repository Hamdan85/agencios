# frozen_string_literal: true

require "securerandom"

module Operations
  module Invoices
    # Registers a client invoice on the active workspace and links the given
    # projects. No payment is opened here — the invoice is created `open` and can
    # later be marked paid, canceled, or have a payment link generated for it
    # (see Operations::Billing::GeneratePaymentLink).
    class Create < Operations::Base
      def initialize(client_id:, amount_cents:, description: nil, due_date: nil, project_ids: [])
        @client_id = client_id
        @amount_cents = amount_cents
        @description = description
        @due_date = due_date
        @project_ids = Array(project_ids).compact
      end

      def call
        client = workspace.clients.find(@client_id)

        invoice = workspace.invoices.new(
          client: client,
          status: :open,
          amount_cents: @amount_cents,
          description: @description,
          due_date: @due_date,
          external_reference: "INV-#{SecureRandom.hex(6).upcase}"
        )
        invoice.save!

        invoice.projects = workspace.projects.where(id: @project_ids) if @project_ids.any?

        invoice
      end
    end
  end
end
