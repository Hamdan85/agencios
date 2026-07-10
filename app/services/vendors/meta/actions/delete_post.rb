# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # Uniform seam entrypoint — deletes a published Post from the network.
      #
      #   Facebook → DELETE /{post_or_video_id} (facebook.md §6 permission table:
      #     pages_manage_posts covers create/edit/delete).
      #   Instagram → the Graph API has no endpoint to delete published media;
      #     raises Vendors::Base::NotSupportedError so the caller can fall back to
      #     a locally-recorded unpublish with a manual-removal note.
      #
      # Raises on failure.
      class DeletePost
        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          if @social_account.provider_instagram?
            raise Vendors::Base::NotSupportedError,
                  I18n.t('vendors.delete_unsupported.instagram')
          end

          raise Vendors::Base::Error, 'Post sem external_post_id.' if @post.external_post_id.blank?

          Vendors::Meta::Client.new(@social_account).delete("/#{@post.external_post_id}")
          true
        end
      end
    end
  end
end
