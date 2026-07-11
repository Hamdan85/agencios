# frozen_string_literal: true

module Operations
  module Tickets
    # The posting step ("Postagem"). The team picks ONE creative per scoped type
    # (the "post bundle") and WHEN to publish (immediate or scheduled). For each
    # connected channel this resolves which of those creatives it can actually
    # receive — dropping media the network doesn't support, and pairing a still
    # cover image (thumbnail/cover type) onto the video post as its cover/thumbnail
    # on thumbnail-capable networks (Instagram Reels, YouTube). One Post per posted
    # creative per channel.
    #
    # The ticket does NOT move to "No ar" here — it only advances to `published`
    # when a post actually succeeds (Operations::Posts::Publish drives that).
    class Publish < Operations::Base
      MODES = %w[immediate scheduled].freeze


      def initialize(ticket:, user:, creative_ids: nil, creative_id: nil, mode: 'immediate', scheduled_at: nil)
        @ticket = ticket
        @user = user
        @creative_ids = (Array(creative_ids).presence || Array(creative_id)).map(&:to_s).compact_blank.uniq
        @mode = mode.to_s.presence_in(MODES) || 'immediate'
        @scheduled_at = scheduled_at
      end

      def call
        validate!
        persist_fields
        posts = build_posts
        if posts.empty?
          raise Operations::Errors::Invalid,
                I18n.t('operations.tickets.no_channel_supports', skipped: skipped_note).strip
        end

        posts.each { |post| PublishPostJob.perform_later(post.id) } if @mode == 'immediate'
        Broadcaster.ticket(@ticket, 'posting_started', mode: @mode, count: posts.size)
        { posts: posts.map(&:id), mode: @mode, scheduled_at: publish_at, skipped: @skipped }
      end

      private

      def validate!
        raise Operations::Errors::Invalid, I18n.t('operations.tickets.select_creative') if creatives.empty?
        if creatives.any? { |c| !c.status_ready? }
          raise Operations::Errors::Invalid, I18n.t('operations.tickets.creative_not_ready')
        end
        raise Operations::Errors::Invalid, I18n.t('operations.tickets.define_channel') if @ticket.channels.blank?
        # An in-flight post must never be dropped mid-publish (the vendor call may
        # already be out — destroying its record would orphan the content on the
        # network, with no unpublish handle and no metrics).
        if @ticket.posts.status_publishing.exists?
          raise Operations::Errors::Invalid,
                I18n.t('operations.tickets.publish_in_progress')
        end
        return unless @mode == 'scheduled' && publish_at.nil?

        raise Operations::Errors::Invalid,
              I18n.t('operations.tickets.define_schedule')
      end

      def creatives
        @creatives ||= @ticket.creatives.where(id: @creative_ids).to_a
      end

      # Immediate posts go out now; scheduled ones at the chosen moment (falls back
      # to the ticket's scheduled_at column).
      def publish_at
        return @publish_at if defined?(@publish_at)

        @publish_at =
          if @mode == 'immediate'
            Time.current
          else
            raw = @scheduled_at.presence || @ticket.scheduled_at
            if raw.is_a?(String)
              begin
                Time.zone.parse(raw)
              rescue StandardError
                nil
              end
            else
              raw
            end
          end
      end

      def persist_fields
        values = { 'creative_ids' => @creative_ids, 'creative_id' => @creative_ids.first, 'post_mode' => @mode }
        values['scheduled_at'] = publish_at if @mode == 'scheduled' && publish_at
        Operations::Tickets::UpdateFields.call(ticket: @ticket, status: 'scheduled', values: values)
      end

      # Fresh start for the PENDING attempts only: scheduled/failed posts are
      # canceled through the posts' own cancel authority; `published` and
      # `unpublished` records are history (metrics, failure trail) and stay;
      # `publishing` (in-flight) is guarded in #validate!. Then build one bound
      # Post per posted creative per connected channel (see #plan_channel).
      def build_posts
        @ticket.posts.where(status: Post.statuses.values_at('scheduled', 'failed')).to_a
               .each { |post| Operations::Posts::Cancel.call(post: post) }
        @skipped = []
        base_caption = @ticket.fields_for('production')['caption']
        captions = @ticket.fields_for('scheduled')['captions']
        captions = captions.is_a?(Hash) ? captions : {}

        client = @ticket.project.client
        @ticket.channels.flat_map do |channel|
          account = client&.social_accounts&.find_by(provider: channel)
          next [] unless account

          caption = captions[channel.to_s].presence || base_caption
          Publishers::PostBundle.for_channel(channel: channel, creatives: creatives, skipped: @skipped).map do |media|
            Operations::Posts::Create.call(
              ticket: @ticket, social_account: account,
              scheduled_at: publish_at, caption: caption, media: media
            )
          end
        end
      end

      def skipped_note
        return '' if @skipped.blank?

        parts = @skipped.map { |s| "#{s[:channel]} (#{media_label(s[:media_kind])})" }
        I18n.t('operations.tickets.skipped_note', items: parts.uniq.join(', '))
      end

      def media_label(kind)
        key = kind.to_s
        I18n.t("operations.tickets.media_labels.#{key}", default: key)
      end
    end
  end
end
