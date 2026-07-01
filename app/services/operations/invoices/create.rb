# frozen_string_literal: true

require "securerandom"

module Operations
  module Invoices
    # Registers a client invoice on the active workspace and links the given
    # projects. No payment is opened here — the invoice is created `open` and can
    # later be marked paid, canceled, or have a payment link generated for it
    # (see Operations::Billing::GeneratePaymentLink).
    class Create < Operations::Base
      def initialize(client_id:, amount_cents:, description: nil, due_date: nil, project_ids: [],
                      send_payment_link: false)
        @client_id = client_id
        @amount_cents = amount_cents
        @description = description
        @due_date = due_date
        @project_ids = Array(project_ids).compact
        @send_payment_link = ActiveModel::Type::Boolean.new.cast(send_payment_link)
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

        charge = generate_payment_link(invoice) if @send_payment_link
        notify_client(invoice, payment_url: charge&.payment_link)
        invoice
      end

      private

      def generate_payment_link(invoice)
        Operations::Billing::GeneratePaymentLink.call(invoice: invoice)
      rescue StandardError => e
        Rails.logger.warn("[Invoices::Create] payment link generation failed: #{e.message}")
        nil
      end

      # Email the client the new invoice (client-facing — guard a missing address).
      def notify_client(invoice, payment_url: nil)
        return if invoice.client&.email.blank?

        InvoiceMailer.created(invoice: invoice, payment_url: payment_url).deliver_later
      rescue StandardError => e
        Rails.logger.warn("[Invoices::Create] invoice email failed: #{e.message}")
      end
    end
  end
end
