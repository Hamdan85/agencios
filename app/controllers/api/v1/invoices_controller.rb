# frozen_string_literal: true

module Api
  module V1
    class InvoicesController < BaseController
      def index  = render_ok(Controllers::Invoices::Index.call(params:))
      def show   = render_ok(Controllers::Invoices::Show.call(params:))
      def create = render_created(Controllers::Invoices::Create.call(params:))
      def update = render_ok(Controllers::Invoices::Update.call(params:))

      # POST /api/v1/invoices/:id/send_invoice
      def send_invoice = render_ok(Controllers::Invoices::SendInvoice.call(params:))

      # POST /api/v1/invoices/:id/cancel
      def cancel = render_ok(Controllers::Invoices::Cancel.call(params:))

      # POST /api/v1/invoices/:id/mark_paid
      def mark_paid = render_ok(Controllers::Invoices::MarkPaid.call(params:))

      # POST /api/v1/invoices/:id/payment_link
      def payment_link = render_ok(Controllers::Invoices::GeneratePaymentLink.call(params:))
    end
  end
end
