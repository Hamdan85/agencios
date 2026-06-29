# frozen_string_literal: true

module Vendors
  module X
    module Actions
      # POST https://api.x.com/2/tweets — create a post (text, media, reply,
      # quote, poll). Returns 201 with { data: { id, text } }. Needs `tweet.write`.
      # See docs/integrations/x-twitter.md §6b.
      class CreatePost
        def self.call(...) = new(...).call

        def initialize(social_account:, text:, media_ids: [], reply_to_tweet_id: nil, quote_tweet_id: nil, extra: {})
          @social_account = social_account
          @text = text
          @media_ids = Array(media_ids).compact
          @reply_to_tweet_id = reply_to_tweet_id
          @quote_tweet_id = quote_tweet_id
          @extra = extra
        end

        # Returns { id:, text: }.
        def call
          body = Vendors::X::Client.new(social_account: @social_account)
                                   .post_json("/2/tweets", payload)
          data = body["data"] || {}
          { id: data["id"], text: data["text"] }
        end

        private

        def payload
          body = { "text" => @text.to_s }
          body["media"] = { "media_ids" => @media_ids } if @media_ids.any?
          body["reply"] = { "in_reply_to_tweet_id" => @reply_to_tweet_id } if @reply_to_tweet_id
          body["quote_tweet_id"] = @quote_tweet_id if @quote_tweet_id
          body.merge(@extra.transform_keys(&:to_s))
        end
      end
    end
  end
end
