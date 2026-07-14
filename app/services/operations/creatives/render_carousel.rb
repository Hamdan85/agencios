# frozen_string_literal: true

require 'open-uri'
require 'base64'

module Operations
  module Creatives
    # The SLOW half of a viral-carousel generation — runs in
    # Creatives::RenderCarouselJob, never in-request. Text + brand identity,
    # rendered as branded HTML→PNG slides (not AI raster images). Claude writes
    # the per-slide copy (Prompts::CarouselCopy), each slide is laid out with the
    # brand's colors, @handle and avatar (Creatives::CarouselSlideTemplate) and
    # rasterized via the headless renderer (Vendors::Render::Html).
    #
    # Image slots are filled only when a slide needs imagery, by priority:
    #   1. the user's uploaded creative images on the ticket
    #   2. free stock (Pexels)
    #   3. AI generation (OpenRouter image model)
    #
    # Results reach the UI via Action Cable (`generation_done` /
    # `creative_ready`); any failure fails the generation and refunds the
    # credits (FailGeneration). The AI vendor cost of the copy (via AiAdapter) +
    # any generated images (OpenRouter) land in the AI ledger (AiUsageLog).
    class RenderCarousel < Operations::Base
      def initialize(generation:)
        @generation       = generation
        @creative         = generation.creative
        @ticket           = @creative&.ticket
        @params           = (generation.params || {}).with_indifferent_access
        @requested_slides = normalize_slides(@params[:slides])
      end

      def call
        @source_url = source_url
        @ctx        = ::Tickets::CreativeContext.for(
          @ticket, creative_type: 'carousel', client: resolve_client, overrides: source_overrides
        )
        @uploads = user_image_queue
        slides   = choose_slides(copy_slides)

        blobs       = render_and_attach(slides)
        slides_meta = slides_metadata(slides, blobs)
        @creative.update!(status: :ready, metadata: { slides: slides_meta })
        @generation.update!(status: :completed, result: { slides: slides_meta })

        Broadcaster.generations(@generation.workspace_id, 'generation_done', id: @generation.id, kind: 'carousel')
        Broadcaster.ticket(@ticket, 'creative_ready', creative_id: @creative.id) if @ticket
        # The RELIABLE autopilot seam — broadcasts are fire-and-forget.
        Operations::Autopilot::OnGenerationSettled.call(generation: @generation)
        @generation
      rescue StandardError => e
        Operations::Creatives::FailGeneration.call(generation: @generation, reason: e.message)
        raise
      end

      private

      # --- slide count ---------------------------------------------------------

      # A numeric request is honored (clamped 3..10); "auto"/blank → nil, letting
      # the model choose the ideal number.
      def normalize_slides(value)
        s = value.to_s.strip.downcase
        return nil if s.empty? || s == 'auto'

        value.to_i.clamp(3, 10)
      end

      # Honor a requested count; otherwise use the model's chosen length (capped
      # at 10). Falls back to a generic deck only if the model returned nothing.
      def choose_slides(copy)
        list = @requested_slides ? copy.first(@requested_slides) : copy
        list = list.first(10)
        list.presence || fallback_slides
      end

      # --- source (idea / text / link) -----------------------------------------

      # The client this carousel is FOR (studio passes client_id; ticket path
      # falls back to the ticket's client inside CreativeContext).
      def resolve_client
        id = @params[:client_id]
        return nil if id.blank?

        workspace.clients.find_by(id: id)
      end

      # The link to base the carousel on, if any. Explicit pasted text wins (then
      # we don't fetch). A URL is honored whether it came from the "link" field OR
      # was pasted into the idea/text.
      def source_url
        return nil if @params[:text].present?

        first_url(@params[:url], @params[:idea], @params[:topic], @params[:text])
      end

      # When a link is the source, Claude reads it directly (web_fetch) — we do
      # NOT scrape or pass its body here, so nothing is truncated. Only a non-URL
      # idea can ride along as the topic; pasted text becomes the source.
      def source_overrides
        {
          topic: source_topic,
          objective: @params[:objective].presence,
          source_text: (@source_url ? nil : @params[:text].presence),
          # Client-requested changes for a regeneration — folded into copy_brief.
          revision_notes: @params[:revision_notes].presence
        }.compact
      end

      # The idea/topic — unless it's just a bare URL, in which case the link
      # content drives the copy instead.
      def source_topic
        topic = @params[:topic].presence || @params[:idea].presence
        return nil if topic&.strip&.match?(%r{\Ahttps?://\S+\z}i)

        topic
      end

      def first_url(*candidates)
        candidates.compact.each do |candidate|
          match = candidate.to_s[%r{https?://\S+}i]
          return match if match
        end
        nil
      end

      # --- copy ----------------------------------------------------------------

      # A carousel's copy is small, so the output cap is set generously to
      # GUARANTEE the JSON is never truncated.
      COPY_MAX_TOKENS = 8000

      def copy_slides
        builder = Prompts::CarouselCopy.new(
          workspace: @ctx.workspace,
          client: @ctx.client,
          slides: @requested_slides,
          topic: @ctx.topic,
          objective: @ctx.objective,
          copy_brief: @ctx.copy_brief,
          script: @ctx.script,
          channels: @ctx.channels.join(', '),
          link_url: @source_url,
          reference_urls: @ctx.reference_urls
        )
        text = AiAdapter.complete(
          builder,
          max_tokens: COPY_MAX_TOKENS,
          operation: 'carousel_copy',
          subject: @ticket,
          web_fetch: @source_url.present? || @ctx.reference_urls.any?
        ).to_s

        parse_slides(text) || link_fallback || fallback_slides
      end

      def parse_slides(text)
        raw = text[/\[.*\]/m]
        return nil unless raw

        data = JSON.parse(raw)
        return nil unless data.is_a?(Array)

        slides = data.select { |h| h.is_a?(Hash) && h['headline'].to_s.present? }
        slides.presence
      rescue JSON::ParserError
        nil
      end

      # Link fallback: only when the model couldn't read the link itself (no API
      # key / error). Scrapes the page (uncapped) and builds a clean deck from it.
      def link_fallback
        return nil unless @source_url

        page = Vendors::Web::Reader.call(url: @source_url)
        return nil unless page

        build_fallback(title: page[:title], body: page[:text])
      end

      # Safety net when the model returns no parseable JSON. Builds a clean deck
      # from the topic + source sentences — never dumps the raw source as a
      # headline.
      def fallback_slides
        build_fallback(title: @ctx.topic, body: @ctx.copy_brief)
      end

      def build_fallback(title:, body:)
        head   = truncate(title.presence || I18n.t('operations.creatives.carousel_default_title'), 60)
        points = sentences(body).first((@requested_slides || 6) - 2)
        points = ['Ponto principal'] if points.empty?

        [{ 'role' => 'hook', 'headline' => head, 'body' => '' }] +
          points.map { |p| { 'role' => 'value', 'headline' => truncate(p, 60), 'body' => '' } } +
          [{ 'role' => 'cta', 'headline' => 'Fale com a gente', 'body' => '' }]
      end

      def sentences(text)
        text.to_s.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:blank?)
      end

      def truncate(text, limit)
        s = text.to_s.strip
        s.length > limit ? "#{s[0, limit - 1].rstrip}…" : s
      end

      # --- render --------------------------------------------------------------

      def render_and_attach(slides)
        width  = @ctx.width  || 1080
        height = @ctx.height || 1350

        htmls = slides.each_with_index.map do |slide, i|
          ::Creatives::CarouselSlideTemplate.render(
            slide: slide,
            index: i + 1,
            total: slides.size,
            width: width,
            height: height,
            primary: @ctx.brand_primary,
            secondary: @ctx.brand_secondary,
            carousel_style: @ctx.carousel_style,
            image_palette: @ctx.carousel_image_palette,
            handle: @ctx.brand_handle,
            brand_name: @ctx.brand_name,
            avatar_uri: avatar_uri,
            logo_uri: logo_uri,
            image_uri: slide_background_uri(slide)
          )
        end

        pngs = Vendors::Render::Html.batch(htmls: htmls, width: width, height: height)
        pngs.each_with_index.map do |png, i|
          blob = ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new(png),
            filename: "slide-#{i + 1}.png",
            content_type: 'image/png'
          )
          @creative.assets.attach(blob)
          blob
        end
      end

      # --- image slots ---------------------------------------------------------

      # Slides are typographic by DEFAULT. An image is added only when the copy
      # explicitly asked for one (slide["image"]). Priority when an image is
      # wanted: the user's uploaded images → Pexels stock → OpenRouter. Returns a
      # data URI or nil (typographic slide).
      def slide_image_uri(slide)
        return nil unless truthy?(slide['image'])

        if (upload = @uploads.shift)
          return attachment_data_uri(upload)
        end

        query = slide['image_query'].to_s.strip.presence || @ctx.topic

        if (photo = stock_photo(query)) && (bytes = fetch_url(photo[:url]))
          return data_uri(bytes, 'image/jpeg')
        end

        generated_image_uri(query)
      end

      def stock_photo(query)
        Vendors::Pexels::Actions::SearchPhoto.call(query: query, aspect_ratio: @ctx.aspect_ratio)
      rescue StandardError => e
        Rails.logger.warn("[RenderCarousel] Pexels failed: #{e.message}")
        nil
      end

      def generated_image_uri(query)
        result = Vendors::OpenRouter::Actions::GenerateImage.call(
          prompt: @ctx.image_prompt(query),
          aspect_ratio: @ctx.image_aspect_ratio
        )
        log_generated_image(result[:cost_cents], model: result[:model])
        data_uri(result[:bytes], result[:content_type])
      rescue Vendors::Base::Error => e
        Rails.logger.warn("[RenderCarousel] image slot failed: #{e.message}")
        nil
      end

      # Uploaded images on this ticket's creatives, newest first, as a consumable
      # queue of ActiveStorage attachments.
      def user_image_queue
        return [] unless @ticket

        @ticket.creatives.where(source: Creative.sources[:uploaded])
               .order(created_at: :desc)
               .flat_map { |c| c.assets.attachments.to_a }
               .select { |a| a.blob&.content_type.to_s.start_with?('image/') }
      end

      # --- brand assets as data URIs ------------------------------------------

      def avatar_uri = @avatar_uri ||= attachment_data_uri(@ctx.avatar)
      def logo_uri   = @logo_uri   ||= attachment_data_uri(@ctx.logo)

      # The client's carousel background image, inlined once (image style only).
      def background_uri
        return @background_uri if defined?(@background_uri)

        @background_uri = @ctx.carousel_style == 'image' ? attachment_data_uri(@ctx.carousel_background) : nil
      end

      # For the image carousel style, every slide is full-bleed over the client's
      # background image (reusing the has-image layout: scrim + white text). Falls
      # back to the normal per-slide image behaviour otherwise, or when the image
      # style is set but no background is attached.
      def slide_background_uri(slide)
        return background_uri if background_uri.present?

        slide_image_uri(slide)
      end

      def attachment_data_uri(att)
        return nil if att.nil?
        return nil if att.respond_to?(:attached?) && !att.attached?

        bytes = att.download
        ct    = att.respond_to?(:content_type) ? att.content_type : att.blob&.content_type
        data_uri(bytes, ct.presence || 'image/png')
      rescue StandardError => e
        Rails.logger.warn("[RenderCarousel] attachment read failed: #{e.message}")
        nil
      end

      def fetch_url(url)
        return nil if url.blank?

        URI.parse(url).open(read_timeout: 15, &:read)
      rescue StandardError => e
        Rails.logger.warn("[RenderCarousel] stock fetch failed: #{e.message}")
        nil
      end

      def data_uri(bytes, content_type)
        "data:#{content_type};base64,#{Base64.strict_encode64(bytes)}"
      end

      # --- bookkeeping ---------------------------------------------------------

      # `url` is the publicly reachable HTTPS blob URL each network vendor's
      # PublishPost reads to build the carousel — must stay in sync with the
      # asset actually attached for this slide (instagram.md §9 / facebook.md §9).
      def slides_metadata(slides, blobs)
        slides.each_with_index.map do |slide, i|
          { index: i + 1, role: slide['role'], headline: slide['headline'], url: blob_url(blobs[i]) }
        end
      end

      def blob_url(blob)
        Rails.application.routes.url_helpers.rails_blob_url(blob, host: SystemConfig.app_host)
      end

      def log_generated_image(cost_cents = nil, model: nil)
        Operations::Ai::LogUsage.call(
          provider: AiUsageLog::PROVIDER_OPENROUTER,
          operation: 'carousel_image',
          model: model.presence || Vendors::OpenRouter::Image::DEFAULT_MODEL,
          units: 1,
          unit_kind: AiUsageLog::UNIT_IMAGE,
          cost_cents: cost_cents,
          subject: @creative
        )
      end

      def truthy?(value)
        [true, 'true', 1, '1'].include?(value)
      end
    end
  end
end
