# frozen_string_literal: true

module Publishers
  # Resolves, for ONE channel, which Post `media` hashes a ticket's ready
  # creatives produce. Three roles fall out of the selection:
  #
  #   - A STORY creative (image or video) publishes to the Stories surface as its
  #     OWN post ({ "story" => true }) on story-capable networks (Instagram), and
  #     is skipped everywhere else — it is never demoted to a feed post.
  #   - A COVER image (thumbnail/cover type, or the explicit `cover:` override
  #     picked at the posting step) rides the video post as its cover/thumbnail
  #     on thumbnail-capable networks; it never posts standalone unless it is a
  #     regular creative doing double duty.
  #   - Everything else posts on its own when the channel supports its media.
  #
  # Anything a channel can't receive is appended to `skipped` (shape:
  # { channel:, creative_type:, media_kind: }).
  class PostBundle
    def self.for_channel(channel:, creatives:, skipped:, cover: nil, account: nil)
      new(channel: channel, creatives: creatives, skipped: skipped, cover: cover, account: account).for_channel
    end

    def initialize(channel:, creatives:, skipped:, cover: nil, account: nil)
      @channel = channel.to_s
      @creatives = Array(creatives)
      @skipped = skipped
      @explicit_cover = cover
      @account = account
    end

    def for_channel
      story_specs + feed_specs
    end

    private

    attr_reader :channel, :creatives, :skipped, :explicit_cover, :account

    # The Stories surface: the story creative's own media (image or video) as its
    # own post. Networks without a story API record the skip instead.
    def story_specs
      return [] unless story

      if story_capable? && supports?(story.media_kind)
        [{ 'creative_id' => story.id.to_s, 'story' => true }]
      else
        skipped << skip(story)
        []
      end
    end

    def feed_specs
      video ? with_video : without_video
    end

    # Combined post: video (main) + cover image riding as its thumbnail.
    def with_video
      media = { 'creative_id' => video.id.to_s }
      media['cover_creative_id'] = cover.id.to_s if cover && thumbnail_capable?

      specs = [media]
      # A cover-ONLY image that can't ride as a thumbnail here has nowhere to go
      # on a video post — record it rather than silently dropping. (An override
      # that is also a selected creative still posts standalone below.)
      skipped << skip(cover) if cover && !thumbnail_capable? && cover_only?(cover)
      extras.each do |creative|
        supports?(creative.media_kind) ? specs << { 'creative_id' => creative.id.to_s } : skipped << skip(creative)
      end
      specs
    end

    # No video for this channel → one post per supported creative; a cover-type
    # image posts standalone (there is no video for it to ride).
    def without_video
      specs = []
      creatives.reject { |c| c == story || cover_type?(c) }.each do |creative|
        supports?(creative.media_kind) ? specs << { 'creative_id' => creative.id.to_s } : skipped << skip(creative)
      end
      cover_type_creatives.each do |creative|
        supports?(creative.media_kind) ? specs << { 'creative_id' => creative.id.to_s } : skipped << skip(creative)
      end
      specs
    end

    def video
      return @video if defined?(@video)

      @video = creatives.find { |c| c != story && c.media_kind == 'video' && supports?('video') }
    end

    # The image that rides the video: the explicit posting-step choice wins over
    # the auto-paired cover-type creative.
    def cover
      return @cover if defined?(@cover)

      @cover = explicit_cover || cover_type_creatives.first
    end

    def story
      return @story if defined?(@story)

      @story = creatives.find { |c| c.creative_type.to_s == 'story' }
    end

    # True when this creative exists ONLY to be a cover — a cover-type creative,
    # or an override that isn't part of the selected bundle. A regular selected
    # creative used as the cover still posts standalone (double duty).
    def cover_only?(creative)
      cover_type?(creative) || creatives.exclude?(creative)
    end

    # Everything not consumed by the combined post posts on its own (e.g. a
    # carousel alongside the video).
    def extras
      creatives - [video, story].compact - cover_type_creatives
    end

    def cover_type_creatives
      @cover_type_creatives ||= creatives.select { |c| cover_type?(c) }
    end

    def cover_type?(creative) = Ticket::COVER_TYPES.include?(creative.creative_type.to_s)
    def supports?(media_kind) = Publishers::SocialPublisher.supports?(channel, media_kind)
    def thumbnail_capable? = Publishers::SocialPublisher.thumbnail_capable?(channel)

    # Stories need the direct vendor pipeline — a PostGate-sourced account has no
    # story endpoint, so the story is skipped (never demoted to a feed post).
    def story_capable?
      return false if account&.connection_source_postgate?

      Publishers::SocialPublisher.story_capable?(channel)
    end

    def skip(creative)
      { channel: channel, creative_type: creative.creative_type, media_kind: creative.media_kind }
    end
  end
end
