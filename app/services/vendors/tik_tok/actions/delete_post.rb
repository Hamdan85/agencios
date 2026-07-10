# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # Uniform seam entrypoint for the unpublish flow. TikTok's Content Posting
      # API has no endpoint to delete a published video (tiktok.md §"Publish
      # video"/"Publish photos" only cover creation) — always raises
      # NotSupportedError; the caller falls back to a locally-recorded unpublish
      # with a manual-removal note.
      class DeletePost
        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
        end

        def call
          raise Vendors::Base::NotSupportedError,
                I18n.t('vendors.delete_unsupported.tiktok')
        end
      end
    end
  end
end
