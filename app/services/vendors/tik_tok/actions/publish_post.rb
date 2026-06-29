# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # Uniform seam entrypoint — performs the FULL TikTok publish flow for a Post:
      #   1. QueryCreatorInfo (MANDATORY before every post; dictates privacy + duration)
      #   2. init video (PULL_FROM_URL by default) OR photo carousel, per the creative
      #   3. poll status/fetch until terminal (PUBLISH_COMPLETE | FAILED)
      #
      # Returns { external_post_id:, permalink: } on success; raises on failure.
      #
      # NOTE on privacy: unaudited apps are clamped to SELF_ONLY. We never hardcode
      # PUBLIC — we pick from the creator's privacy_level_options (SELF_ONLY first if
      # present), exactly as TikTok review requires.
      class PublishPost
        POLL_ATTEMPTS = 30
        POLL_INTERVAL = 2 # seconds; status/fetch is capped at 30 req/min per token.

        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          creator = Vendors::TikTok::Actions::QueryCreatorInfo.call(@social_account)
          validate_creator!(creator)

          publish_id = photo_post?(creator) ? init_photo(creator) : init_video(creator)
          raise Vendors::Base::Error, "TikTok did not return a publish_id" if publish_id.blank?

          status = poll_until_terminal(publish_id)
          unless status["status"] == "PUBLISH_COMPLETE"
            raise Vendors::Base::Error, "TikTok publish failed: #{status["fail_reason"] || status["status"]}"
          end

          { external_post_id: external_post_id(status, publish_id), permalink: permalink(status) }
        end

        private

        def validate_creator!(creator)
          options = Array(creator["privacy_level_options"])
          raise Vendors::Base::Error, "TikTok creator cannot post (no privacy options)" if options.empty?
        end

        def privacy_level(creator)
          options = Array(creator["privacy_level_options"])
          options.include?("SELF_ONLY") ? "SELF_ONLY" : options.first
        end

        # A creative with image slides → photo carousel; otherwise a video.
        def photo_post?(_creator)
          photo_urls.any?
        end

        def init_video(creator)
          Vendors::TikTok::Actions::PublishVideo.call(
            social_account: @social_account,
            post_info: video_post_info(creator),
            video_url: video_url
          )
        end

        def init_photo(creator)
          Vendors::TikTok::Actions::PublishPhoto.call(
            social_account: @social_account,
            post_info: photo_post_info(creator),
            photo_images: photo_urls,
            photo_cover_index: 0
          )
        end

        def video_post_info(creator)
          {
            title: @post.caption.to_s,
            privacy_level: privacy_level(creator),
            disable_duet: false,
            disable_comment: false,
            disable_stitch: false,
            video_cover_timestamp_ms: 1000,
            brand_content_toggle: false,
            brand_organic_toggle: false,
            is_aigc: false
          }
        end

        def photo_post_info(creator)
          {
            title: @post.caption.to_s.truncate(90),
            description: @post.caption.to_s,
            privacy_level: privacy_level(creator),
            disable_comment: false,
            auto_add_music: true,
            brand_content_toggle: false,
            brand_organic_toggle: false
          }
        end

        def poll_until_terminal(publish_id)
          status = {}
          POLL_ATTEMPTS.times do
            status = Vendors::TikTok::Actions::FetchPublishStatus.call(
              social_account: @social_account, publish_id: publish_id
            )
            break if %w[PUBLISH_COMPLETE FAILED SEND_TO_USER_INBOX].include?(status["status"])

            sleep(POLL_INTERVAL)
          end
          status
        end

        # `publicaly_available_post_id` (TikTok's typo) is a list, present only once a
        # public post clears moderation. Fall back to the publish_id otherwise.
        def external_post_id(status, publish_id)
          Array(status["publicaly_available_post_id"]).first || publish_id
        end

        def permalink(status)
          post_id = Array(status["publicaly_available_post_id"]).first
          username = @social_account.username
          return nil if post_id.blank? || username.blank?

          "https://www.tiktok.com/@#{username}/video/#{post_id}"
        end

        # --- media resolution from the ticket's creatives -----------------------

        def creative
          @creative ||= @post.ticket.creatives.order(created_at: :desc).first
        end

        # Public URL of the first attached video asset (PULL_FROM_URL needs a verified
        # domain in production; presigned/temporary links fail url_ownership_unverified).
        def video_url
          asset = creative&.assets&.first
          return nil if asset.blank?

          Rails.application.routes.url_helpers.rails_blob_url(asset, host: SystemConfig.app_host)
        end

        # Carousel image URLs from creative.metadata.slides, else attached image assets.
        def photo_urls
          @photo_urls ||= begin
            slides = creative&.metadata&.dig("slides")
            if slides.present?
              Array(slides).filter_map { |s| s.is_a?(Hash) ? s["url"] : s }
            else
              Array(creative&.assets).filter_map do |asset|
                next unless asset.content_type.to_s.start_with?("image/")

                Rails.application.routes.url_helpers.rails_blob_url(asset, host: SystemConfig.app_host)
              end
            end
          end
        end
      end
    end
  end
end
