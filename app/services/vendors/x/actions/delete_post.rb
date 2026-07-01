# frozen_string_literal: true

module Vendors
  module X
    module Actions
      # Uniform seam entrypoint — DELETE /2/tweets/:id (tweet.write scope, same
      # scope already granted for CreatePost). Returns { deleted: true } on
      # success per the X v2 API; raises on failure.
      class DeletePost
        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          raise Vendors::Base::Error, 'Post sem external_post_id.' if @post.external_post_id.blank?

          Vendors::X::Client
            .new(social_account: @social_account)
            .delete_json("/2/tweets/#{@post.external_post_id}")
          true
        end
      end
    end
  end
end
