# frozen_string_literal: true

module Controllers
  module Invoices
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        invoices = workspace.invoices.includes(:client).order(created_at: :desc)
        invoices = invoices.where(status: @params[:status]) if @params[:status].present?
        invoices = invoices.where(client_id: @params[:client_id]) if @params[:client_id].present?
        { invoices: serialize_collection(invoices, InvoiceSerializer) }
      end
    end
  end
end
