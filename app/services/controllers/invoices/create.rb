# frozen_string_literal: true

module Controllers
  module Invoices
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        invoice = Operations::Invoices::Create.call(
          client_id:    create_params[:client_id],
          amount_cents: create_params[:amount_cents],
          description:  create_params[:description],
          due_date:     create_params[:due_date],
          project_ids:  create_params[:project_ids] || []
        )
        { invoice: serialize(invoice, InvoiceSerializer) }
      end

      private

      def create_params
        @create_params ||= @params.require(:invoice).permit(
          :client_id, :amount_cents, :description, :due_date,
          project_ids: []
        )
      end
    end
  end
end
