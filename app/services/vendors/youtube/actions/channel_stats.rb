# frozen_string_literal: true

module Vendors
  module Youtube
    module Actions
      # Lifetime channel totals via channels.list?part=statistics&mine=true (§7.2, 1 unit).
      # Returns the `statistics` hash: { viewCount, subscriberCount, hiddenSubscriberCount,
      # videoCount }. Scope: youtube.readonly.
      class ChannelStats
        def self.call(...) = new(...).call

        def initialize(social_account:)
          @social_account = social_account
        end

        def call
          body = Vendors::Youtube::Client
                 .new(access_token: @social_account.user_access_token)
                 .list_channels(part: "statistics")
          item = Array(body["items"]).first || {}
          item["statistics"] || {}
        end
      end
    end
  end
end
