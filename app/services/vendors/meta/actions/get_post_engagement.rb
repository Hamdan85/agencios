# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB per-post engagement from the post OBJECT (not /insights): reactions,
      # comments and shares. These summary fields are long-standing and stable —
      # unlike the insights metrics, they aren't part of Meta's reach/impressions
      # deprecation churn, so likes/comments/shares keep populating. Returns the
      # raw Graph body: { reactions: { summary: { total_count } }, comments: {…},
      # shares: { count } }. See docs/integrations/meta.md §7d.
      class GetPostEngagement
        def self.call(...) = new(...).call

        FIELDS = 'shares,comments.summary(true),reactions.summary(true)'

        def initialize(social_account:, post_id:, client: nil)
          @social_account = social_account
          @post_id = post_id
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.get("/#{@post_id}", params: { fields: FIELDS })
        end
      end
    end
  end
end
