# frozen_string_literal: true

module Vendors
  module Postgate
    module Actions
      # Uniform seam entrypoint — publishes a Post through PostGate for any
      # postgate-sourced SocialAccount (Publishers::SocialPublisher routes here
      # when SocialAccount#connection_source_postgate?).
      #
      # No scheduled_at is ever sent — our own scheduler (PublishPostJob) decides
      # WHEN to call publish, so PostGate is always asked to publish immediately.
      #
      # PostGate delivery is async server-side. A single short poll window (5
      # tries, 4s apart) covers the common case; anything still in flight after
      # that returns `pending: true` and Operations::Posts::Publish hands off to
      # Posts::PollPostgateStatusJob instead of finishing synchronously.
      #
      # Returns on success:      { external_post_id:, permalink:, postgate_post_id: }
      # Returns when still in flight: { pending: true, postgate_post_id: }
      # Raises Vendors::Base::Error on a terminal target failure (failed/skipped).
      class PublishPost
        POLL_ATTEMPTS = 5
        POLL_INTERVAL = 4 # seconds
        TITLE_LIMIT = 100

        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
          @client = Vendors::Postgate::Client.new
        end

        def call
          created = @client.create_post(payload, idempotency_key: idempotency_key)
          poll_until_settled(created['id'])
        end

        private

        def payload
          {
            post: { body: @post.caption.to_s, options: platform_options },
            profiles: [@social_account.postgate_profile_id],
            media: media_urls
          }
        end

        def idempotency_key
          "agencios-#{@post.id}-#{@post.updated_at.to_i}"
        end

        def poll_until_settled(postgate_post_id)
          pg_post = nil
          POLL_ATTEMPTS.times do |i|
            pg_post = @client.get_post(postgate_post_id)
            target = Array(pg_post['targets']).first || {}

            case target['status']
            when 'published'
              return { external_post_id: target['platform_post_id'], permalink: target['permalink'],
                        postgate_post_id: pg_post['id'] }
            when 'failed', 'skipped'
              raise Vendors::Base::Error, target['error_message'].presence || "PostGate target #{target['status']}"
            end

            sleep(POLL_INTERVAL) if i < POLL_ATTEMPTS - 1
          end

          { pending: true, postgate_post_id: pg_post ? pg_post['id'] : postgate_post_id }
        end

        # --- platform-specific options -------------------------------------------

        def platform_options
          case @social_account.provider
          when 'youtube' then { youtube: youtube_options }
          when 'pinterest' then { pinterest: { board_id: pinterest_board_id } }
          else {}
          end
        end

        def youtube_options
          {
            title: youtube_title,
            privacy: 'public',
            made_for_kids: false,
            community_guidelines_confirmed: true
          }
        end

        # Mirrors Vendors::Youtube::Actions::PublishPost#title: first caption
        # line, truncated to 100 chars ("#Shorts" appended for a flagged short).
        def youtube_title
          base = @post.caption.to_s.split("\n").first.to_s.strip
          base = 'Video' if base.empty?
          short = !!creative&.metadata&.dig('short')
          base = base.truncate(short ? TITLE_LIMIT - 8 : TITLE_LIMIT)
          short ? "#{base} #Shorts" : base
        end

        def pinterest_board_id
          configured = @social_account.postgate_meta['board_id'].presence
          return configured if configured

          board = @client.list_boards(@social_account.postgate_profile_id)['data']&.first
          raise Vendors::Base::Error, I18n.t('vendors.postgate.no_board') if board.blank?

          board['id']
        end

        # --- media resolution (mirrors Vendors::Meta::Actions::PublishPost) -----

        def creative
          @creative ||= @post.publishable_creative
        end

        def media_urls
          return [video_url] if video_url.present?
          return image_urls if image_urls.present?

          []
        end

        def video_url
          return @video_url if defined?(@video_url)

          asset = Array(creative&.assets).find { |a| a.content_type.to_s.start_with?('video/') }
          @video_url = asset ? blob_url(asset) : nil
        end

        # Carousel image URLs from creative.metadata.slides, falling back to
        # attached image assets when the slides don't carry a url (e.g. older
        # metadata format) — the attached assets are always the source of truth.
        def image_urls
          @image_urls ||= metadata_image_urls.presence || asset_image_urls
        end

        def metadata_image_urls
          slides = creative&.metadata&.dig('slides')
          return [] if slides.blank?

          Array(slides).filter_map { |s| s.is_a?(Hash) ? s['url'] : s }
        end

        def asset_image_urls
          Array(creative&.assets).filter_map do |asset|
            next unless asset.content_type.to_s.start_with?('image/')

            blob_url(asset)
          end
        end

        def blob_url(asset)
          Rails.application.routes.url_helpers.rails_blob_url(asset, host: SystemConfig.app_host)
        end
      end
    end
  end
end
