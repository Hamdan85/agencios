# frozen_string_literal: true

module Controllers
  module PushSubscriptions
    # Removes a browser push subscription by endpoint (sent as the :id param,
    # URL-encoded by the frontend).
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        user.push_subscriptions.find_by(endpoint: @params[:id])&.destroy
        { ok: true }
      end
    end
  end
end
