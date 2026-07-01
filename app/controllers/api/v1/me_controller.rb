# frozen_string_literal: true

module Api
  module V1
    class MeController < BaseController
      # Identity must be readable behind the paywall — the SPA reads billing
      # status from here to decide whether to render the paywall.
      skip_billing_gate

      def show = render_ok(Controllers::Me::Show.call)
    end
  end
end
