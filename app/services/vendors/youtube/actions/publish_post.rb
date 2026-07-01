# frozen_string_literal: true

module Vendors
  module Youtube
    module Actions
      # Uniform seam entrypoint — performs the FULL YouTube publish flow for a Post:
      # resumable upload of the ticket's video creative (§6) → returns the video id +
      # watch URL. Builds the snippet/status metadata from the post's caption.
      #
      # Returns { external_post_id: <videoId>, permalink: "https://youtube.com/watch?v=<id>" }.
      # Raises on failure.
      #
      # Shorts (§6.5): no separate API field — a vertical 9:16, ≤3-min file with
      # "#Shorts" in the title/description is auto-classified. If the creative is
      # flagged short (metadata["short"] truthy), we append "#Shorts" to the title.
      class PublishPost
        TITLE_LIMIT = 100
        DESCRIPTION_LIMIT = 5_000
        DEFAULT_CATEGORY = "22" # People & Blogs

        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          bytes = video_bytes
          raise Vendors::Base::Error, "No video creative to upload for post #{@post.id}" if bytes.blank?

          video_id = Vendors::Youtube::Actions::UploadVideo.call(
            social_account: @social_account,
            bytes: bytes,
            metadata: metadata,
            notify_subscribers: true
          )

          { external_post_id: video_id, permalink: "https://youtube.com/watch?v=#{video_id}" }
        end

        private

        def metadata
          {
            snippet: {
              title: title,
              description: caption.to_s.truncate(DESCRIPTION_LIMIT),
              categoryId: DEFAULT_CATEGORY,
              defaultLanguage: "pt-BR"
            },
            status: {
              privacyStatus: privacy_status,
              selfDeclaredMadeForKids: false, # COPPA flag — must be set deliberately.
              embeddable: true,
              license: "youtube",
              containsSyntheticMedia: ai_generated?
            }
          }
        end

        # Title from caption's first line, capped at 100 chars; "#Shorts" appended for shorts.
        def title
          base = caption.to_s.split("\n").first.to_s.strip
          base = "Video" if base.empty?
          base = base.truncate(short? ? TITLE_LIMIT - 8 : TITLE_LIMIT)
          short? ? "#{base} #Shorts" : base
        end

        # Scheduled posts upload as private until publish; published posts go public.
        def privacy_status
          @post.status_published? ? "public" : "private"
        end

        def caption
          @post.caption
        end

        def creative
          @creative ||= @post.publishable_creative
        end

        def short?
          !!creative&.metadata&.dig("short")
        end

        def ai_generated?
          creative&.source_generated? || false
        end

        # Download the first attached video asset's bytes for the resumable upload.
        def video_bytes
          asset = Array(creative&.assets).find { |a| a.content_type.to_s.start_with?("video/") }
          asset ||= creative&.assets&.first
          asset&.download
        end
      end
    end
  end
end
