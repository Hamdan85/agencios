# frozen_string_literal: true

module Vendors
  module Postgate
    module Actions
      # Uniform seam entrypoint for the unpublish flow — DELETE /api/posts/{id}
      # through PostGate. Raises NotSupportedError when there is no PostGate post
      # id on record (e.g. the post never made it past `pending` before being
      # unpublished) — the caller falls back to a locally-recorded unpublish with
      # a manual-removal note, same as the direct vendors' unsupported paths.
      class DeletePost
        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
        end

        def call
          if @post.postgate_post_id.blank?
            raise Vendors::Base::NotSupportedError, I18n.t('vendors.postgate.delete_missing_post_id')
          end

          Vendors::Postgate::Client.new.delete_post(@post.postgate_post_id)
          true
        end
      end
    end
  end
end
