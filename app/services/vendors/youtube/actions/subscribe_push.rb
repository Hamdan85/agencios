# frozen_string_literal: true

module Vendors
  module Youtube
    module Actions
      # Subscribes to PubSubHubbub push notifications for new uploads on a channel
      # (§8). Optional — not needed for the upload/analytics flows. The hub later GETs
      # the callback with hub.challenge (echo it back, 200) and POSTs Atom XML on new
      # uploads. Leases expire (~5-10 days) → re-subscribe before expiry.
      class SubscribePush
        def self.call(...) = new(...).call

        def initialize(channel_id:, callback_url:, mode: 'subscribe')
          @channel_id = channel_id
          @callback_url = callback_url
          @mode = mode
        end

        def call
          client = Vendors::Youtube::Client.new
          client.subscribe_push(
            callback_url: @callback_url,
            topic_url: client.feed_topic_url(@channel_id),
            mode: @mode
          )
        end
      end
    end
  end
end
