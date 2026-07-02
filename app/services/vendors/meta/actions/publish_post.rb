# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # Uniform seam entrypoint — performs the FULL Meta publish flow for a Post,
      # branching on the connected network (instagram.md §6 / facebook.md §6):
      #
      #   Instagram → create container(s) → poll status (Reels) → media_publish.
      #     - single image  : CreateMediaContainer → PublishMedia
      #     - carousel       : CreateCarouselItem×N → CreateCarouselContainer → PublishMedia
      #     - reel/video     : CreateReelsContainer (hosted URL) → poll FINISHED → PublishMedia
      #   Facebook → choose by media type:
      #     - text/link      : CreateFeedPost
      #     - single photo   : CreatePagePhoto (published=true)
      #     - multi-photo    : CreatePagePhoto(published=false)×N → CreateFeedPost(attached_media)
      #     - reel/video     : StartReelUpload → UploadReelBinary(file_url) → poll → FinishReel
      #
      # Returns { external_post_id:, permalink: }. Raises on failure.
      class PublishPost
        POLL_ATTEMPTS = 30
        POLL_INTERVAL = 5 # seconds; container processing is async (instagram.md §6c).

        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          if @social_account.provider_instagram?
            publish_instagram
          else
            publish_facebook
          end
        end

        private

        # ---- Instagram --------------------------------------------------------

        def publish_instagram
          creation_id =
            if video_url.present?
              build_reel_container
            elsif image_urls.size > 1
              build_carousel_container
            else
              build_single_image_container
            end

          # Container processing is async on Meta's side (reel transcode, carousel
          # child ingestion, image fetch). Publishing before the container is
          # FINISHED returns "Media ID is not available" — wait for it, exactly as
          # the Reel path already did (instagram.md §6c).
          poll_ig_container!(creation_id)
          media = PublishMedia.call(social_account: @social_account, creation_id:)
          media_id = media['id']
          reshare_to_story if share_to_story?
          { external_post_id: media_id, permalink: ig_permalink(media_id) }
        end

        # The combined post flow: after the Reel is live, reshare the SAME video to
        # the account's story (a STORIES container of the same video_url). Set at
        # the posting step via media["share_to_story"]. Best-effort — a story
        # failure must never fail the feed post.
        def share_to_story?
          video_url.present? && @post.media.is_a?(Hash) && @post.media['share_to_story']
        end

        def reshare_to_story
          creation_id = CreateStoryContainer.call(
            social_account: @social_account, video_url: video_url
          ).fetch('id')
          poll_ig_container!(creation_id)
          story = PublishMedia.call(social_account: @social_account, creation_id:)
          stash_story_id(story['id']) if story.is_a?(Hash)
        rescue StandardError => e
          Rails.logger.warn("[Meta::PublishPost] story reshare failed for post #{@post.id}: #{e.message}")
        end

        def stash_story_id(id)
          return if id.blank?

          @post.update!(media: @post.media.merge('story_external_id' => id))
        rescue StandardError
          nil
        end

        def build_single_image_container
          url = image_urls.first
          raise Vendors::Base::Error, 'Nenhuma mídia para publicar no Instagram.' if url.blank?

          CreateMediaContainer.call(
            social_account: @social_account, image_url: url, caption: @post.caption
          ).fetch('id')
        end

        def build_carousel_container
          child_ids = image_urls.first(10).map do |url|
            CreateCarouselItem.call(social_account: @social_account, image_url: url).fetch('id')
          end
          CreateCarouselContainer.call(
            social_account: @social_account, child_ids:, caption: @post.caption
          ).fetch('id')
        end

        def build_reel_container
          CreateReelsContainer.call(
            social_account: @social_account, video_url:, caption: @post.caption, cover_url:
          ).fetch('id')
        end

        # Poll the container until FINISHED (publishable); raise on ERROR/EXPIRED.
        # Used for every IG container type — reel, carousel and single image — since
        # all of them ingest/process asynchronously before they can be published.
        def poll_ig_container!(creation_id)
          POLL_ATTEMPTS.times do
            status = GetContainerStatus.call(social_account: @social_account, creation_id:)
            code = status['status_code']
            return if %w[FINISHED PUBLISHED].include?(code)
            raise Vendors::Base::Error, "O processamento da mídia falhou: #{code}" if %w[ERROR EXPIRED].include?(code)

            sleep(POLL_INTERVAL)
          end
          raise Vendors::Base::Error, 'Tempo esgotado aguardando o processamento da mídia.'
        end

        def ig_permalink(media_id)
          return nil if media_id.blank?

          media = Vendors::Meta::Client.new(@social_account)
                                       .get("/#{media_id}", params: { fields: 'permalink' })
          media['permalink']
        rescue Vendors::Base::Error
          nil
        end

        # ---- Facebook ---------------------------------------------------------

        def publish_facebook
          if video_url.present?
            publish_facebook_reel
          elsif image_urls.size > 1
            publish_facebook_gallery
          elsif image_urls.size == 1
            publish_facebook_photo
          else
            publish_facebook_text
          end
        end

        def publish_facebook_text
          result = CreateFeedPost.call(
            social_account: @social_account, message: @post.caption, link: @post.media['link']
          )
          fb_result(result['id'])
        end

        def publish_facebook_photo
          result = CreatePagePhoto.call(
            social_account: @social_account, url: image_urls.first, caption: @post.caption
          )
          fb_result(result['post_id'] || result['id'])
        end

        def publish_facebook_gallery
          media_fbids = image_urls.first(10).map do |url|
            CreatePagePhoto.call(
              social_account: @social_account, url:, published: false
            ).fetch('id')
          end
          attached = media_fbids.map { |id| { 'media_fbid' => id } }
          result = CreateFeedPost.call(
            social_account: @social_account, message: @post.caption, attached_media: attached
          )
          fb_result(result['id'])
        end

        def publish_facebook_reel
          started = StartReelUpload.call(social_account: @social_account)
          video_id = started.fetch('video_id')

          # Have Meta pull the public URL rather than streaming bytes ourselves.
          UploadReelBinary.call(
            social_account: @social_account, video_id:, file_url: video_url
          )
          poll_fb_video!(video_id)
          FinishReel.call(
            social_account: @social_account, video_id:, description: @post.caption, video_state: 'PUBLISHED'
          )
          fb_result(video_id)
        end

        # Poll FB video/Reel processing until ready/publishing (facebook.md §6e).
        def poll_fb_video!(video_id)
          POLL_ATTEMPTS.times do
            status = GetVideoStatus.call(social_account: @social_account, video_id:)
            phase = status.dig('status', 'processing_phase', 'status') ||
                    status.dig('status', 'video_status')
            return if %w[complete ready].include?(phase.to_s)
            raise Vendors::Base::Error, 'Processamento do vídeo do Facebook falhou.' if phase.to_s == 'error'

            sleep(POLL_INTERVAL)
          end
          raise Vendors::Base::Error, 'Tempo esgotado aguardando o processamento do vídeo do Facebook.'
        end

        def fb_result(post_or_video_id)
          { external_post_id: post_or_video_id, permalink: fb_permalink(post_or_video_id) }
        end

        def fb_permalink(id)
          return nil if id.blank?

          "https://www.facebook.com/#{id}"
        end

        # ---- media resolution (shared) ---------------------------------------

        def creative
          @creative ||= @post.publishable_creative
        end

        # An optional still image the team paired with this video at the posting
        # step (thumbnail/cover creative type) → the Reel's cover_url. Nil for
        # non-video posts, in which case CreateReelsContainer simply omits it.
        def cover_url
          return @cover_url if defined?(@cover_url)

          cover = @post.cover_creative
          asset = Array(cover&.assets).find { |a| a.content_type.to_s.start_with?('image/') } || cover&.assets&.first
          @cover_url = asset ? blob_url(asset) : nil
        end

        # First attached video asset's public URL (Meta fetches the bytes; must be
        # publicly reachable HTTPS at publish time — instagram.md §9 / facebook.md §9).
        def video_url
          return @video_url if defined?(@video_url)

          asset = Array(creative&.assets).find { |a| a.content_type.to_s.start_with?('video/') }
          @video_url = asset ? blob_url(asset) : nil
        end

        # Carousel/gallery image URLs from creative.metadata.slides, falling back to
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
