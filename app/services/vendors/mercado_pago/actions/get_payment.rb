# frozen_string_literal: true

module Vendors
  module MercadoPago
    module Actions
      # GET /v1/payments/{id} — the AUTHORITATIVE payment status read.
      #
      # Webhooks carry only `data.id`, never trustworthy state; always read the
      # real status here. Pass the owning `workspace` so a marketplace-connected
      # agency's own OAuth token is used (falls back to the platform token).
      #
      # See docs/integrations/mercado-pago.md §3 ("never trust the webhook body").
      #
      #   Vendors::MercadoPago::Actions::GetPayment.call("999999999", workspace: ws)
      #   # => { "id" => ..., "status" => "approved", "external_reference" => ..., ... }
      class GetPayment
        def self.call(...) = new(...).call

        def initialize(payment_id, workspace: nil, client: nil)
          @payment_id = payment_id
          @client = client || Vendors::MercadoPago::Client.new(workspace: workspace)
        end

        def call
          @client.get_payment(@payment_id)
        end
      end
    end
  end
end
