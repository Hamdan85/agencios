# frozen_string_literal: true

module Controllers
  module Webhooks
    module Meta
      # GET handshake — returns the hub.challenge to echo back, or nil if the
      # verify token does not match (controller → 403).
      class VerifySubscription < Controllers::Base
        def initialize(params:)
          @params = params
        end

        def call
          Vendors::Meta::Webhook.verify_subscription(
            mode: @params['hub.mode'],
            token: @params['hub.verify_token'],
            challenge: @params['hub.challenge']
          )
        end
      end
    end
  end
end
