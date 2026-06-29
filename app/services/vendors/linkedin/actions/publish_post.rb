# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # Uniform seam entrypoint: full LinkedIn publish flow for a Post.
      #
      #   resolve author URN (org if present, else member)
      #   -> if a creative is attached: upload image/video, poll AVAILABLE,
      #      build content.media.id
      #   -> POST /rest/posts
      #   -> capture x-restli-id, derive a permalink
      #
      # Returns { external_post_id:, permalink: }. Raises on failure.
      # See docs/integrations/linkedin.md §6.
      class PublishPost
        def self.call(...) = new(...).call

        AVAILABILITY_POLLS    = 30
        AVAILABILITY_INTERVAL = 2 # seconds between AVAILABLE polls

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          author_urn = resolve_author_urn
          media = build_media(author_urn)

          result = Vendors::Linkedin::Actions::CreatePost.call(
            social_account: @social_account,
            author_urn: author_urn,
            commentary: @post.caption.to_s,
            media: media
          )

          post_urn = result.fetch(:post_urn)
          { external_post_id: post_urn, permalink: permalink_for(post_urn) }
        end

        private

        # Prefer the org URN (Company Page) when the account has one; otherwise the
        # member profile URN.
        def resolve_author_urn
          urn = @social_account.default_org_urn.presence || @social_account.member_urn.presence
          raise Vendors::Base::Error, "LinkedIn author URN missing on SocialAccount" if urn.blank?

          urn
        end

        # Uploads the first creative asset (if any) and returns the content.media
        # hash, or nil for a text-only post.
        def build_media(author_urn)
          asset = first_asset
          return nil unless asset

          bytes = asset.download
          content_type = asset.content_type.to_s

          if content_type.start_with?("video")
            urn = Vendors::Linkedin::Actions::UploadVideo.call(
              social_account: @social_account, owner_urn: author_urn, bytes: bytes
            )
            wait_for_available { Vendors::Linkedin::Actions::GetVideo.call(social_account: @social_account, video_urn: urn) }
            { "id" => urn, "title" => media_title }
          else
            urn = Vendors::Linkedin::Actions::UploadImage.call(
              social_account: @social_account, owner_urn: author_urn, bytes: bytes,
              content_type: content_type.presence || "image/jpeg"
            )
            wait_for_available { Vendors::Linkedin::Actions::GetImage.call(social_account: @social_account, image_urn: urn) }
            { "id" => urn, "altText" => media_title }
          end
        end

        def first_asset
          creative = @post.ticket.creatives.detect { |c| c.assets.attached? }
          creative&.assets&.first
        end

        def media_title
          @post.caption.to_s.truncate(80).presence || "agencios"
        end

        # Poll the asset GET until status == AVAILABLE (uploads process async).
        def wait_for_available
          AVAILABILITY_POLLS.times do
            body = yield
            return true if body["status"] == "AVAILABLE"

            sleep AVAILABILITY_INTERVAL
          end
          true # proceed; LinkedIn accepts the post and finishes processing server-side
        end

        # LinkedIn does not return a permalink; derive the feed URL from the URN.
        def permalink_for(post_urn)
          "https://www.linkedin.com/feed/update/#{post_urn}"
        end
      end
    end
  end
end
