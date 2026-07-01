# frozen_string_literal: true

module Operations
  module Tickets
    # The posting step ("Postagem"). The team chooses WHICH creative goes out and
    # WHEN (immediate or scheduled); this builds one Post per connected channel
    # bound to that creative, and either publishes now or leaves the posts for the
    # scheduled sweep (MonitorScheduledPostsJob) to publish when due.
    #
    # The ticket does NOT move to "No ar" here — it only advances to `published`
    # when a post actually succeeds (Operations::Posts::Publish drives that).
    class Publish < Operations::Base
      MODES = %w[immediate scheduled].freeze

      def initialize(ticket:, user:, creative_id:, mode: "immediate", scheduled_at: nil)
        @ticket = ticket
        @user = user
        @creative_id = creative_id
        @mode = mode.to_s.presence_in(MODES) || "immediate"
        @scheduled_at = scheduled_at
      end

      def call
        validate!
        persist_fields
        posts = build_posts
        if posts.empty?
          raise Operations::Errors::Invalid,
                "Nenhum canal conectado suporta este criativo (#{media_label}). #{skipped_note}".strip
        end

        posts.each { |post| PublishPostJob.perform_later(post.id) } if @mode == "immediate"
        Broadcaster.ticket(@ticket, "posting_started", mode: @mode, count: posts.size)
        { posts: posts.map(&:id), mode: @mode, scheduled_at: publish_at, skipped: @skipped }
      end

      private

      def validate!
        raise Operations::Errors::Invalid, "Selecione um criativo para postar." if creative.nil?
        raise Operations::Errors::Invalid, "O criativo selecionado ainda não está pronto." unless creative.status_ready?
        raise Operations::Errors::Invalid, "Defina ao menos um canal." if @ticket.channels.blank?
        raise Operations::Errors::Invalid, "Defina a data e hora do agendamento." if @mode == "scheduled" && publish_at.nil?
      end

      def creative
        @creative ||= @ticket.creatives.find_by(id: @creative_id)
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
        values = { "creative_id" => @creative_id.to_s, "post_mode" => @mode }
        values["scheduled_at"] = publish_at if @mode == "scheduled" && publish_at
        Operations::Tickets::UpdateFields.call(ticket: @ticket, status: "scheduled", values: values)
      end

      # Fresh start: drop prior unpublished posts so the chosen creative + timing
      # win, then create one bound Post per connected channel that SUPPORTS this
      # creative's media kind (e.g. an image never posts to video-only TikTok).
      def build_posts
        @ticket.posts.where.not(status: Post.statuses[:published]).destroy_all
        @skipped = []

        client = @ticket.project.client
        @ticket.channels.filter_map do |channel|
          account = client&.social_accounts&.find_by(provider: channel)
          next unless account

          unless Publishers::SocialPublisher.supports?(channel, media_kind)
            @skipped << channel
            next
          end

          Operations::Posts::Create.call(
            ticket: @ticket,
            social_account: account,
            scheduled_at: publish_at,
            caption: @ticket.fields_for("production")["caption"],
            media: { "creative_id" => @creative_id.to_s }
          )
        end
      end

      def media_kind = @media_kind ||= creative.media_kind

      def media_label
        { "image" => "imagem", "carousel" => "carrossel", "video" => "vídeo", "text" => "texto" }[media_kind] || media_kind
      end

      def skipped_note
        return "" if @skipped.blank?

        "Canais ignorados (não suportam #{media_label}): #{@skipped.join(', ')}."
      end
    end
  end
end
