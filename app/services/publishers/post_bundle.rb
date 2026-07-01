# frozen_string_literal: true

module Publishers
  # Resolves, for ONE channel, which Post `media` hashes a ticket's ready
  # creatives produce. The key rule: a video + a cover image + a story creative
  # collapse into a SINGLE post — the video is the media, the cover rides as its
  # thumbnail (on thumbnail-capable networks), and the story creative is a FLAG
  # that the published video should be reshared to the story (on story-capable
  # networks). It is NOT posted as a separate story.
  #
  # When there is no video for the channel, it falls back to the previous
  # behavior (one post per supported creative; a cover image posts standalone),
  # so single-creative and image-only tickets are unchanged.
  #
  # Anything a channel can't receive is appended to `skipped` (shape:
  # { channel:, creative_type:, media_kind: }).
  class PostBundle
    # Networks whose API can reshare a published video to the story. Only
    # Instagram is implemented (Vendors::Meta STORIES container); everywhere else
    # a story creative is dropped rather than split into its own post.
    STORY_CAPABLE = %w[instagram].freeze

    def self.for_channel(channel:, creatives:, skipped:)
      new(channel: channel, creatives: creatives, skipped: skipped).for_channel
    end

    def initialize(channel:, creatives:, skipped:)
      @channel = channel.to_s
      @creatives = Array(creatives)
      @skipped = skipped
    end

    def for_channel
      video ? with_video : without_video
    end

    private

    attr_reader :channel, :creatives, :skipped

    # Combined post: video (main) + cover (thumbnail) + story (reshare flag).
    def with_video
      media = { 'creative_id' => video.id.to_s }
      media['cover_creative_id'] = cover.id.to_s if cover && thumbnail_capable?
      apply_story(media)

      specs = [media]
      # A cover that can't ride as a thumbnail here has nowhere to go on a video
      # post — record it rather than silently dropping.
      skipped << skip(cover) if cover && !thumbnail_capable?
      extras.each do |creative|
        supports?(creative.media_kind) ? specs << { 'creative_id' => creative.id.to_s } : skipped << skip(creative)
      end
      specs
    end

    def apply_story(media)
      return unless story

      if story_capable?
        media['share_to_story'] = true
      else
        skipped << skip(story)
      end
    end

    # No video for this channel → previous per-creative behavior (backward compat).
    def without_video
      specs = []
      creatives.reject { |c| cover_type?(c) }.each do |creative|
        supports?(creative.media_kind) ? specs << { 'creative_id' => creative.id.to_s } : skipped << skip(creative)
      end
      if cover
        supports?(cover.media_kind) ? specs << { 'creative_id' => cover.id.to_s } : skipped << skip(cover)
      end
      specs
    end

    def video
      return @video if defined?(@video)

      @video = creatives.find { |c| c.media_kind == 'video' && supports?('video') }
    end

    def cover
      return @cover if defined?(@cover)

      @cover = creatives.find { |c| cover_type?(c) }
    end

    def story
      return @story if defined?(@story)

      @story = creatives.find { |c| c.creative_type.to_s == 'story' }
    end

    # Everything not consumed by the combined post posts on its own (e.g. a
    # carousel alongside the video).
    def extras
      creatives - [video, cover, story].compact
    end

    def cover_type?(creative) = Ticket::COVER_TYPES.include?(creative.creative_type.to_s)
    def supports?(media_kind) = Publishers::SocialPublisher.supports?(channel, media_kind)
    def thumbnail_capable? = Publishers::SocialPublisher.thumbnail_capable?(channel)
    def story_capable? = STORY_CAPABLE.include?(channel)

    def skip(creative)
      { channel: channel, creative_type: creative.creative_type, media_kind: creative.media_kind }
    end
  end
end
