# frozen_string_literal: true

module Controllers
  module Webhooks
    module Social
      # GET handshake for the Instagram-Login and Threads webhook endpoints. The
      # verify token is shared (meta.webhook_verify_token); the signature scheme is
      # the same Meta-family HMAC, so we reuse Vendors::Meta::Webhook. Returns the
      # hub.challenge to echo, or nil (→ controller 403).
      class VerifySubscription < Controllers::Base
        def initialize(provider:, params:)
          @provider = provider.to_s
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
