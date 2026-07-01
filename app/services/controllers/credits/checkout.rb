# frozen_string_literal: true

module Controllers
  module Credits
    # POST /api/v1/credits/checkout — start a Stripe Checkout to buy a credit
    # pack. Returns the redirect URL; the wallet is credited by the webhook.
    class Checkout < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        pack = Pricing.credit_pack(@params[:pack])
        raise Operations::Errors::Invalid, "Pacote de créditos inválido." unless pack

        session = Vendors::Stripe::Actions::CreateCreditCheckoutSession.call(
          workspace:   workspace,
          pack:        pack,
          success_url: "#{SystemConfig.app_host}/assinatura?credits=success",
          cancel_url:  "#{SystemConfig.app_host}/assinatura?credits=cancelled"
        )
        { url: session.url }
      rescue Vendors::Base::NotConfiguredError
        { url: "#{SystemConfig.app_host}/assinatura?credits=mock" }
      end
    end
  end
end
