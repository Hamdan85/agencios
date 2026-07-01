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

      MEDIA_LABELS = { "image" => "imagem", "carousel" => "carrossel", "video" => "vídeo", "text" => "texto" }.freeze

      def initialize(ticket:, user:, creative_ids: nil, creative_id: nil, mode: "immediate", scheduled_at: nil)
        @ticket = ticket
        @user = user
        @creative_ids = (Array(creative_ids).presence || Array(creative_id)).map(&:to_s).compact_blank.uniq
        @mode = mode.to_s.presence_in(MODES) || "immediate"
        @scheduled_at = scheduled_at
      end

      def call
        validate!
        persist_fields
        posts = build_posts
        if posts.empty?
          raise Operations::Errors::Invalid,
                "Nenhum canal conectado suporta os criativos selecionados. #{skipped_note}".strip
        end

        posts.each { |post| PublishPostJob.perform_later(post.id) } if @mode == "immediate"
        Broadcaster.ticket(@ticket, "posting_started", mode: @mode, count: posts.size)
        { posts: posts.map(&:id), mode: @mode, scheduled_at: publish_at, skipped: @skipped }
      end

      private

      def validate!
        raise Operations::Errors::Invalid, "Selecione ao menos um criativo para postar." if creatives.empty?
        raise Operations::Errors::Invalid, "Há um criativo selecionado que ainda não está pronto." if creatives.any? { |c| !c.status_ready? }
        raise Operations::Errors::Invalid, "Defina ao menos um canal." if @ticket.channels.blank?
        raise Operations::Errors::Invalid, "Defina a data e hora do agendamento." if @mode == "scheduled" && publish_at.nil?
      end

      def creatives
        @creatives ||= @ticket.creatives.where(id: @creative_ids).to_a
      end

      # Immediate posts go out now; scheduled ones at the chosen moment (falls back
      # to the ticket's scheduled_at column).
      def publish_at
        return @publish_at if defined?(@publish_at)

        @publish_at =
          if @mode == "immediate"
            Time.current
          else
            raw = @scheduled_at.presence || @ticket.scheduled_at
            raw.is_a?(String) ? (Time.zone.parse(raw) rescue nil) : raw
          end
      end

      def persist_fields
        values = { "creative_ids" => @creative_ids, "creative_id" => @creative_ids.first, "post_mode" => @mode }
        values["scheduled_at"] = publish_at if @mode == "scheduled" && publish_at
        Operations::Tickets::UpdateFields.call(ticket: @ticket, status: "scheduled", values: values)
      end

      # Fresh start: drop prior unpublished posts, then build one bound Post per
      # posted creative per connected channel (see #plan_channel for the routing).
      def build_posts
        @ticket.posts.where.not(status: Post.statuses[:published]).destroy_all
        @skipped = []
        caption = @ticket.fields_for("production")["caption"]

        client = @ticket.project.client
        @ticket.channels.flat_map do |channel|
          account = client&.social_accounts&.find_by(provider: channel)
          next [] unless account

          plan_channel(channel).map do |media|
            Operations::Posts::Create.call(
              ticket: @ticket, social_account: account,
              scheduled_at: publish_at, caption: caption, media: media
            )
          end
        end
      end

      # Which creatives actually post on `channel`, as an array of Post `media`
      # hashes. A cover image (thumbnail/cover type) rides a video post as its
      # cover on thumbnail-capable networks; otherwise it is a standalone image
      # post where supported, else dropped. Everything the channel can't receive is
      # recorded in @skipped.
      def plan_channel(channel)
        has_video = creatives.any? { |c| c.media_kind == "video" && supports?(channel, "video") }
        cover = creatives.find { |c| cover_type?(c) }
        attach_cover = cover && has_video && Publishers::SocialPublisher.thumbnail_capable?(channel)

        specs = []
        creatives.reject { |c| cover_type?(c) }.each do |c|
          unless supports?(channel, c.media_kind)
            @skipped << skip(channel, c)
            next
          end

          media = { "creative_id" => c.id.to_s }
          media["cover_creative_id"] = cover.id.to_s if attach_cover && c.media_kind == "video"
          specs << media
        end

        if cover && !attach_cover
          if supports?(channel, cover.media_kind)
            specs << { "creative_id" => cover.id.to_s }
          else
            @skipped << skip(channel, cover)
          end
        end

        specs
      end

      def cover_type?(creative)
        Ticket::COVER_TYPES.include?(creative.creative_type.to_s)
      end

      def supports?(channel, media_kind)
        Publishers::SocialPublisher.supports?(channel, media_kind)
      end

      def skip(channel, creative)
        { channel: channel, creative_type: creative.creative_type, media_kind: creative.media_kind }
      end

      def skipped_note
        return "" if @skipped.blank?

        parts = @skipped.map { |s| "#{s[:channel]} (#{MEDIA_LABELS[s[:media_kind].to_s] || s[:media_kind]})" }
        "Ignorados: #{parts.uniq.join(', ')}."
      end
    end
  end
end
