# frozen_string_literal: true

module Api
  module V1
    class CreditsController < BaseController
      # Buying credits must work behind the paywall (an active workspace with a
      # drained wallet still needs to top up); reading the balance too.
      skip_billing_gate

      def show     = render_ok(Controllers::Credits::Show.call)
      def checkout = render_ok(Controllers::Credits::Checkout.call(params:))
    end
  end
end
