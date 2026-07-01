# frozen_string_literal: true

module Vendors
  module Threads
    module Actions
      # Uniform seam entrypoint — full Threads publish flow for a Post (threads.md
      # §6): create a media container, poll processing for media, then publish.
      #   - text only : POST /{user}/threads?media_type=TEXT
      #   - single img: media_type=IMAGE&image_url=…
      #   - single vid: media_type=VIDEO&video_url=…  (poll status)
      #   - carousel  : item containers (is_carousel_item) → media_type=CAROUSEL&children=…
      # Then POST /{user}/threads_publish?creation_id=… → media id.
      # Returns { external_post_id:, permalink: }. Raises on failure.
      class PublishPost
        POLL_ATTEMPTS = 30
        POLL_INTERVAL = 5 # seconds; media container processing is async.

        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @account = post.social_account
          @client = Vendors::Threads::Client.new(@account)
        end

        def call
          creation_id =
            if video_url.present?
              build_video_container
            elsif image_urls.size > 1
              build_carousel_container
            elsif image_urls.size == 1
              build_image_container
            else
              build_text_container
            end

          media = @client.post("/#{user_id}/threads_publish", params: { creation_id: })
          media_id = media['id']
          { external_post_id: media_id, permalink: permalink(media_id) }
        end

        private

        def user_id = @account.external_user_id

        def build_text_container
          raise Vendors::Base::Error, 'Nada para publicar no Threads.' if @post.caption.blank?

          create_container(media_type: 'TEXT', text: @post.caption).fetch('id')
        end

        def build_image_container
          create_container(media_type: 'IMAGE', image_url: image_urls.first, text: @post.caption).fetch('id')
        end

        def build_video_container
          id = create_container(media_type: 'VIDEO', video_url:, text: @post.caption).fetch('id')
          poll_container!(id)
          id
        end

        def build_carousel_container
          children = image_urls.first(20).map do |url|
            create_container(media_type: 'IMAGE', image_url: url, is_carousel_item: true).fetch('id')
          end
          id = create_container(media_type: 'CAROUSEL', children: children.join(','), text: @post.caption).fetch('id')
          poll_container!(id)
          id
        end

        def create_container(**params)
          @client.post("/#{user_id}/threads", params:)
        end

        # Poll the container until FINISHED (publishable); raise on ERROR/EXPIRED.
        def poll_container!(creation_id)
          POLL_ATTEMPTS.times do
            status = @client.get("/#{creation_id}", params: { fields: 'status,error_message' })
            code = status['status']
            return if %w[FINISHED PUBLISHED].include?(code)
            raise Vendors::Base::Error, "Container do Threads falhou: #{status['error_message'] || code}" if %w[ERROR
                                                                                                                EXPIRED].include?(code)

            sleep(POLL_INTERVAL)
          end
          raise Vendors::Base::Error, 'Tempo esgotado aguardando o processamento da mídia no Threads.'
        end

        def permalink(media_id)
          return nil if media_id.blank?

          @client.get("/#{media_id}", params: { fields: 'permalink' })['permalink']
        rescue Vendors::Base::Error
          nil
        end

        # ---- media resolution (mirrors Vendors::Meta::Actions::PublishPost) ----

        def creative
          @creative ||= @post.publishable_creative
        end

        def video_url
          return @video_url if defined?(@video_url)

          asset = Array(creative&.assets).find { |a| a.content_type.to_s.start_with?('video/') }
          @video_url = asset ? blob_url(asset) : nil
        end

        def image_urls
          @image_urls ||= begin
            slides = creative&.metadata&.dig('slides')
            if slides.present?
              Array(slides).filter_map { |s| s.is_a?(Hash) ? s['url'] : s }
            else
              Array(creative&.assets).filter_map do |asset|
                next unless asset.content_type.to_s.start_with?('image/')

                blob_url(asset)
              end
            end
          end
        end

        def blob_url(asset)
          Rails.application.routes.url_helpers.rails_blob_url(asset, host: SystemConfig.app_host)
        end
      end
    end
  end
end
